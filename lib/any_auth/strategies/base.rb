# frozen_string_literal: true

module AnyAuth
  module Strategies
    class Base
      include ActiveModel::Model
      include ActiveModel::Attributes

      attr_writer :provider

      def self.provider
        name.demodulize.underscore
      end

      def self.fields?
        attribute_names.any?
      end

      def provider
        @provider || self.class.provider
      end

      def refresh(credentials)
        credentials
      end

      def inspect
        "#<#{self.class.name} provider=#{provider.inspect}>"
      end

      private

      def secure_compare(expected, given)
        expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected.to_s, given.to_s)
      end

      def error_from(status, body, headers = {})
        code = error_code(body)

        error_class_for(code, status).new(
          "#{provider} returned #{code || status || 'an error'}",
          code:,
          description: error_description(body),
          retry_after: retry_after(headers),
        )
      end

      def error_code(body)
        body['error']
      end

      def error_description(body)
        body['error_description']
      end

      def error_class_for(code, status)
        case code
        when 'invalid_client', 'invalid_request',
             'unsupported_grant_type', 'unsupported_response_type'
          ConfigurationError
        when 'server_error', 'temporarily_unavailable'
          Unavailable
        else
          error_class_for_status(status)
        end
      end

      def error_class_for_status(status)
        case status
        when nil, 400, 401, 403 then AccessDenied
        else Unavailable
        end
      end

      def retry_after(headers)
        value = headers['retry-after'].to_s
        return if value.blank?
        return value.to_i if value.match?(/\A\d+\z/)

        [(Time.httpdate(value) - Time.current).ceil, 0].max
      rescue ArgumentError
        nil
      end
    end
  end
end
