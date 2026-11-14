# frozen_string_literal: true

module AnyAuth
  module Strategies
    class Apple < OpenIDConnect
      ISSUER = 'https://appleid.apple.com'

      self.pkce = false

      attr_accessor :team_id, :key_id, :private_key

      def request_phase(redirect_uri:, scope: self.scope || 'email name', **params)
        super(redirect_uri:, scope:, **params, response_mode: 'form_post')
      end

      def callback_phase(params, session)
        auth = super

        auth.with(info: auth.info.with(name: full_name(params['user'])))
      end

      def client_secret
        claims = {
          iss: team_id,
          sub: client_id,
          aud: ISSUER,
          iat: Time.current.to_i,
          exp: 5.minutes.from_now.to_i,
        }

        JWT.encode(claims, OpenSSL::PKey.read(private_key), 'ES256', { kid: key_id })
      end

      def client_options
        {
          site: ISSUER,
          authorize_url: '/auth/authorize',
          token_url: '/auth/token',
          auth_scheme: :request_body,
        }
      end

      private

      def identity_from(claims)
        raise Unauthorized, 'Invalid issuer' unless claims['iss'] == ISSUER

        { uid: fetch_claim(claims, 'sub'), info: info_from(claims) }
      end

      def info_from(claims)
        Info.new(email: claims['email'], email_verified: claims['email_verified'].to_s == 'true')
      end

      def full_name(user)
        user = JSON.parse(user.to_s)
        name = user['name'] if user.is_a?(Hash)
        return unless name.is_a?(Hash)

        name.values_at('firstName', 'lastName').compact_blank.join(' ').presence
      rescue JSON::ParserError
        nil
      end
    end
  end
end
