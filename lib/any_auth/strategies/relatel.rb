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

      def state_echoed?(_params, _session)
        true
      end

      def identity(token, _session)
        employee = asked_with(token, '/api/v2/employee').fetch('employee', {})
        raise Unauthorized, 'relatel named no company for this token' if employee['company_id'].blank?

        { uid: employee['company_id'].to_s, raw: employee }
      end
    end
  end
end
