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

      def expired?(_credentials)
        false
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

      def error_class_for(status)
        case status
        when nil, 400, 401, 403 then Unauthorized
        when 429 then RateLimited
        else Unavailable
        end
      end
    end
  end
end
