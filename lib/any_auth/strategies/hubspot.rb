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
        portal = asked_with(token, "/oauth/v1/access-tokens/#{token.token}")
        raise Unauthorized, 'hubspot named no portal for this token' if portal['hub_id'].blank?

        { uid: portal['hub_id'].to_s, info: Info.new(name: portal['hub_domain']), raw: portal }
      end
    end
  end
end
