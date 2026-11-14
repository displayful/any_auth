# frozen_string_literal: true

module AnyAuth
  module Strategies
    class Shopify < OAuth
      attribute :shop, :string

      validates :shop, format: { with: /\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/, message: :invalid }

      def shop=(value)
        super(normalize_shop(value))
      end

      def client_options
        raise ArgumentError, "#{shop.inspect} is not a Shopify shop" unless valid?

        {
          site: URI::HTTPS.build(host: shop).to_s,
          authorize_url: '/admin/oauth/authorize',
          token_url: '/admin/oauth/access_token',
        }
      end

      private

      def normalize_shop(value)
        address = value.to_s.strip.downcase.delete_prefix('https://').delete_prefix('http://')
        name = address[%r{\Aadmin\.shopify\.com/store/([^/]+)}, 1] || address.split('/').first
        return if name.blank?
        return name if name.include?('.')

        "#{name}.myshopify.com"
      end

      def verify(params, session)
        super
        raise InvalidCallback, 'Invalid shop' unless shop.present? && params['shop'] == shop
        raise InvalidCallback, 'Invalid HMAC' unless valid_hmac?(params)
      end

      def valid_hmac?(params)
        return false unless client_secret.present? && params.values.all?(String)

        secure_compare(hmac(params), params['hmac'])
      end

      def hmac(params)
        message = params.except('hmac').sort.map { it.join('=') }.join('&')

        OpenSSL::HMAC.hexdigest('SHA256', client_secret, message)
      end

      def exchange(code, session)
        super(code, session, expiring: 1)
      end

      def identity(access_token, _session)
        { uid: shop, raw: access_token.params }
      end
    end
  end
end
