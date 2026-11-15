# frozen_string_literal: true

module AnyAuth
  module Strategies
    class Hubspot < OAuth2
      self.pkce = true

      def client_options
        {
          site: 'https://api.hubspot.com',
          authorize_url: 'https://app.hubspot.com/oauth/authorize',
          token_url: '/oauth/2026-09/token',
        }
      end

      private

      def identity(access_token, _session)
        token_info = introspect(access_token.token)
        raise AccessDenied, "#{provider} returned no user" unless named_user?(token_info)

        {
          uid: token_info['user_id'].to_s,
          info: Info.new(email: token_info['user']),
          raw: token_info.except('token'),
        }
      end

      def introspect(token)
        body = { client_id:, client_secret:, token_type_hint: 'access_token', token: }

        parsed { client.request(:post, '/oauth/2026-09/token/introspect', body:, snaky: false) }
      end

      def named_user?(token_info)
        token_info['active'] == true && token_info['user_id'].present?
      end
    end
  end
end
