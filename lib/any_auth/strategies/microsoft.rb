# frozen_string_literal: true

module AnyAuth
  module Strategies
    class Microsoft < OpenIDConnect
      authorize_option :prompt, :login_hint, :domain_hint

      def client_options
        {
          site: 'https://login.microsoftonline.com',
          authorize_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
          token_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
          auth_scheme: :request_body,
        }
      end

      private

      def identity_from(claims)
        issued = issued_by_its_tenant?(claims)
        raise Unauthorized, 'The ID token was not issued by a Microsoft tenant' unless issued

        { uid: "#{claims['tid']}:#{required(claims, 'oid')}", info: info_from(claims) }
      end

      def info_from(claims)
        Info.new(name: claims['name'], email: claims['email'], email_verified: vouched_for?(claims))
      end

      def issued_by_its_tenant?(claims)
        tenant = claims['tid'].to_s

        tenant.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) &&
          claims['iss'] == "https://login.microsoftonline.com/#{tenant}/v2.0"
      end

      def vouched_for?(claims)
        !personal_account?(claims) && claims['xms_edov'].to_s.in?(%w[true 1])
      end

      def personal_account?(claims)
        claims['tid'] == '9188040d-6c67-4c5b-b112-36a304b66dad'
      end
    end
  end
end
