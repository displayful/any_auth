module AnyAuth
  module Strategies
    class OpenIDConnect < OAuth
      def request_phase(redirect_uri:, scope: self.scope || 'email profile', **params)
        nonce = SecureRandom.hex(16)
        pkce = PKCE.pair
        request = super(redirect_uri:, **params, scope: with_openid(scope), nonce:,
          code_challenge: pkce.challenge, code_challenge_method: 'S256')

        request.with(session: request.session.merge('nonce' => nonce, 'code_verifier' => pkce.verifier))
      end

      private

      def with_openid(scope)
        ['openid', *scope.split].uniq.join(' ')
      end

      def exchange(code, session)
        super(code, session, code_verifier: session['code_verifier'])
      end

      def identity(token, session)
        claims = claims_in(token)
        raise Unauthorized, "The ID token from #{provider} is not for this sign-in" unless for_us?(claims, session)

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

        client_id.present? && audiences.include?(client_id) && claims['azp'].in?([nil, client_id]) &&
          (audiences.one? || claims['azp'] == client_id)
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
