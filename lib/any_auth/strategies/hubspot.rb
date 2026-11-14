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
    end
  end
end
