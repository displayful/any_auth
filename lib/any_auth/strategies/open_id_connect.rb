module AnyAuth
  module Strategies
    class OpenIDConnect < OAuth
      self.pkce = true

      def request_phase(redirect_uri:, scope: self.scope || 'email profile', **params)
        nonce = SecureRandom.hex(16)
        request = super(redirect_uri:, **params, scope: with_openid(scope), nonce:)

        request.with(session: request.session.merge('nonce' => nonce))
      end

      private

      def with_openid(scope)
        ['openid', *scope.split].uniq.join(' ')
      end

      def identity(token, session)
        claims = claims_in(token)
        ours = for_us?(claims, session)
        raise Unauthorized, "The ID token from #{provider} is not for this sign-in" unless ours

        identity_from(claims).merge(raw: claims)
      end

      def claims_in(token)
        claims = JWT.decode(token.params.fetch('id_token'), nil, false).first
        return claims if claims.is_a?(Hash)

        raise Unauthorized, "#{provider} sent an ID token that says nothing"
      rescue JWT::DecodeError, KeyError, ArgumentError, TypeError
        raise Unauthorized, "#{provider} sent no ID token we can read"
      end

      def for_us?(claims, session)
        issued_to_us?(claims) && unexpired?(claims) && same?(session['nonce'], claims['nonce'])
      end

      def issued_to_us?(claims)
        audiences = Array(claims['aud'])
        party = claims['azp']

        client_id.present? && audiences.include?(client_id) && party.in?([nil, client_id]) &&
          (audiences.one? || party == client_id)
      end

      def unexpired?(claims)
        claims['exp'].is_a?(Numeric) && Time.at(claims['exp']).future?
      end

      def required(claims, name)
        value = claims[name]
        return value if value.is_a?(String) && value.present?

        raise Unauthorized, "The ID token from #{provider} has no #{name}"
      end
    end
  end
end
