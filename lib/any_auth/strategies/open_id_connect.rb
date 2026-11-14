module AnyAuth
  module Strategies
    class OpenIDConnect < OAuth
      def request_phase(redirect_uri:, scope: self.scope || 'email profile', **params)
        nonce = SecureRandom.hex(16)
        pkce = PKCE.pair
        request = super(redirect_uri:, scope: with_openid(scope), nonce:,
          code_challenge: pkce.challenge, code_challenge_method: 'S256', **params)

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
        JWT.decode(token.params.fetch('id_token'), nil, false).first
      rescue JWT::DecodeError, KeyError
        raise Unauthorized, "#{provider} sent no ID token we can read"
      end

      def for_us?(claims, session)
        Array(claims['aud']).include?(client_id) && Time.at(claims['exp'].to_i).future? &&
          same?(session['nonce'], claims['nonce'])
      end

      def required(claims, name)
        claims[name].presence || raise(Unauthorized, "The ID token from #{provider} has no #{name}")
      end
    end
  end
end
