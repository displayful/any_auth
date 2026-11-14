# frozen_string_literal: true

module AnyAuth
  module Strategies
    class Hubspot < OAuth
      def client_options
        {
          site: 'https://api.hubapi.com',
          authorize_url: 'https://app.hubspot.com/oauth/authorize',
          token_url: 'https://api.hubapi.com/oauth/v1/token',
          auth_scheme: :request_body,
        }
      end

      private

      def identity(token, _session)
        token_info = get(token, "/oauth/v1/access-tokens/#{token.token}")
        raise Unauthorized, "#{provider} returned no user" if token_info['user_id'].blank?

        {
          uid: token_info['user_id'].to_s,
          info: Info.new(email: token_info['user']),
          raw: token_info.except('token'),
        }
      end
    end
  end
end
