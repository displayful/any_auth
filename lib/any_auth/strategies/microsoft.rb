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
        tenant = claims['tid'].to_s

        unless tenant.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) &&
               claims['iss'] == "https://login.microsoftonline.com/#{tenant}/v2.0"
          raise Unauthorized, 'The ID token was not issued by a Microsoft tenant'
        end

        personal = tenant == '9188040d-6c67-4c5b-b112-36a304b66dad'
        vouched = !personal && claims['xms_edov'].to_s.in?(%w[true 1])

        { uid: "#{tenant}:#{required(claims, 'oid')}", info: Info.new(email: claims['email'], email_verified: vouched) }
      end
    end
  end
end
