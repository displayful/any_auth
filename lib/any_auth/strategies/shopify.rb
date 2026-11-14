module AnyAuth
  module Strategies
    class Shopify < OAuth
      attribute :shop, :string

      validates :shop, format: { with: /\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/, message: :invalid }

      def shop=(value)
        typed = value.to_s.strip.downcase.sub(%r{\Ahttps?://}, '')
        name = typed[%r{\Aadmin\.shopify\.com/store/([^/]+)}, 1] || typed.split('/').first.to_s
        name = "#{name}.myshopify.com" if name.present? && name.exclude?('.')

        super(name.presence)
      end

      def client_options
        {
          site: "https://#{shop}",
          authorize_url: '/admin/oauth/authorize',
          token_url: "https://#{shop}/admin/oauth/access_token",
          auth_scheme: :request_body,
        }
      end

      def authorization(credentials)
        { 'X-Shopify-Access-Token' => credentials['access_token'].to_s }
      end

      private

      def verify(params, session)
        super
        return if client_secret.present? && shop.present? && params['shop'] == shop &&
                  ActiveSupport::SecurityUtils.secure_compare(signature_of(params), params['hmac'].to_s)

        raise InvalidCallback, "The callback is not signed by Shopify for #{shop}"
      end

      def exchange(code, session)
        super(code, session, expiring: 1)
      end

      def signature_of(params)
        OpenSSL::HMAC.hexdigest('SHA256', client_secret, params.except('hmac').sort.map { it.join('=') }.join('&'))
      end
    end
  end
end
