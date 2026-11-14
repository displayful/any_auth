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

      def fresh(credentials)
        credentials
      end

      def authorization(_credentials)
        {}
      end
    end
  end
end
