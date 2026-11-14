# frozen_string_literal: true

module AnyAuth
  module Strategies
    class Apple < OpenIDConnect
      self.pkce = false

      attr_accessor :team_id, :key_id, :private_key

      def request_phase(redirect_uri:, scope: self.scope || 'email name', **params)
        super(redirect_uri:, scope:, **params, response_mode: 'form_post')
      end

      def callback_phase(params, session)
        auth = super

        auth.with(info: auth.info.with(name: name_in(params['user'])))
      end

      def client_secret
        claims = {
          iss: team_id,
          sub: client_id,
          aud: 'https://appleid.apple.com',
          iat: Time.current.to_i,
          exp: 5.minutes.from_now.to_i,
        }

        JWT.encode(claims, OpenSSL::PKey.read(private_key), 'ES256', { kid: key_id })
      end

      def client_options
        {
          site: 'https://appleid.apple.com',
          authorize_url: '/auth/authorize',
          token_url: '/auth/token',
          auth_scheme: :request_body,
        }
      end

      private

      def identity_from(claims)
        raise Unauthorized, 'The ID token was not issued by Apple' unless issued_by_apple?(claims)

        { uid: required(claims, 'sub'), info: info_from(claims) }
      end

      def issued_by_apple?(claims)
        claims['iss'] == 'https://appleid.apple.com'
      end

      def info_from(claims)
        Info.new(email: claims['email'], email_verified: claims['email_verified'].to_s == 'true')
      end

      def name_in(user)
        user = JSON.parse(user.to_s)
        name = user['name'] if user.is_a?(Hash)

        name.values_at('firstName', 'lastName').compact_blank.join(' ').presence if name.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
