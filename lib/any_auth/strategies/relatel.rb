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

      def identity(token, _session)
        employee = asked_with(token, '/api/v2/employee')['employee']
        raise Unauthorized, 'relatel named no employee for this token' unless employee.is_a?(Hash) && employee['id']

        { uid: employee['id'].to_s, info: Info.new(name: employee['name'], email: employee['email']), raw: employee }
      end
    end
  end
end
