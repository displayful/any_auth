module AnyAuth
  module Strategies
    class OpenIDConnect < OAuth
      def request_phase(redirect_uri:, scope: self.scope || 'email profile', **params)
        pkce = PKCE.pair
        nonce = SecureRandom.hex(16)
        asked = { scope: ['openid', *scope.split].uniq.join(' '), nonce:, code_challenge: pkce.challenge }
        request = super(redirect_uri:, code_challenge_method: 'S256', **asked, **params)

        request.with(session: request.session.merge('nonce' => nonce, 'code_verifier' => pkce.verifier))
      end

      private

      def exchange(code, session)
        super(code, session, code_verifier: session['code_verifier'])
      end

      def identity(token, session)
        claims = JWT.decode(token.params.fetch('id_token'), nil, false).first
        raise Unauthorized, "The ID token from #{provider} is not for this sign-in" unless for_us?(claims, session)

        identity_from(claims)
      rescue JWT::DecodeError, KeyError
        raise Unauthorized, "#{provider} sent no ID token we can read"
      end

      def for_us?(claims, session)
        Array(claims['aud']).include?(client_id) && Time.at(claims['exp'].to_i).future? && session['nonce'].present? &&
          ActiveSupport::SecurityUtils.secure_compare(claims['nonce'].to_s, session['nonce'].to_s)
      end

      def required(claims, name)
        claims[name].presence || raise(Unauthorized, "The ID token from #{provider} has no #{name}")
      end
    end
  end
end
