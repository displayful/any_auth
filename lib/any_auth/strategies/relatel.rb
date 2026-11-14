# frozen_string_literal: true

module AnyAuth
  module Strategies
    class Relatel < OAuth
      self.pkce = true

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
        employee = get(token, '/api/v2/employee')['employee']
        employee = {} unless employee.is_a?(Hash)
        raise Unauthorized, "#{provider} returned no employee" if employee['id'].blank?

        {
          uid: employee['id'].to_s,
          info: Info.new(name: employee['name'], email: employee['email']),
          raw: employee,
        }
      end
    end
  end
end
