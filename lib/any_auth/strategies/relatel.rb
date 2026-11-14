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
        }
      end

      private

      def identity(access_token, _session)
        employee = get(access_token, '/api/v2/employee')['employee'] || {}
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
