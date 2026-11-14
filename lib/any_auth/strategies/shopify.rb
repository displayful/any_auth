module AnyAuth
  module Strategies
    class Shopify < OAuth
      attribute :shop, :string

      validates :shop, format: { with: /\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/, message: :invalid }

      def shop=(typed)
        super(shop_domain_in(typed))
      end

      def client_options
        {
          site: URI::HTTPS.build(host: shop).to_s,
          authorize_url: '/admin/oauth/authorize',
          token_url: '/admin/oauth/access_token',
          auth_scheme: :request_body,
        }
      end

      private

      def shop_domain_in(typed)
        address = typed.to_s.strip.downcase.delete_prefix('https://').delete_prefix('http://')
        name = address[%r{\Aadmin\.shopify\.com/store/([^/]+)}, 1] || address.split('/').first
        return if name.blank?

        name.include?('.') ? name : "#{name}.myshopify.com"
      end

      def verify(params, session)
        super
        raise InvalidCallback, 'The callback is for another shop' unless shop.present? && params['shop'] == shop
        raise InvalidCallback, 'The callback is not signed by Shopify' unless signed_by_shopify?(params)
      end

      def signed_by_shopify?(params)
        client_secret.present? && same?(signature_of(params), params['hmac'])
      end

      def exchange(code, session)
        super(code, session, expiring: 1)
      end

      def identity(token, _session)
        { uid: shop, raw: token.params }
      end

      def signature_of(params)
        OpenSSL::HMAC.hexdigest('SHA256', client_secret, params.except('hmac').sort.map { it.join('=') }.join('&'))
      end
    end
  end
end
