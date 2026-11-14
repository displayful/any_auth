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
        token_info = asked_with(token, "/oauth/v1/access-tokens/#{token.token}")
        raise Unauthorized, 'hubspot named no user for this token' if token_info['user_id'].blank?

        { uid: token_info['user_id'].to_s, info: Info.new(email: token_info['user']), raw: token_info }
      end
    end
  end
end
