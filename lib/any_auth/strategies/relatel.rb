module AnyAuth
  module Strategies
    class Relatel < OAuth
      def client_options
        {
          site: 'https://app.relatel.dk',
          authorize_url: '/api/v2/authorize',
          token_url: 'https://app.relatel.dk/api/v2/token',
          auth_scheme: :request_body,
        }
      end

      private

      def state?(_params, _session)
        true
      end
    end
  end
end
