module AnyAuth
  module Strategies
    class Google < OpenIDConnect
      authorize_option :access_type, :prompt, :hd, :login_hint

      def client_options
        {
          site: 'https://www.googleapis.com',
          authorize_url: 'https://accounts.google.com/o/oauth2/v2/auth',
          token_url: 'https://oauth2.googleapis.com/token',
          auth_scheme: :request_body,
        }
      end

      private

      def identity_from(claims)
        unless claims['iss'].in?(%w[https://accounts.google.com accounts.google.com])
          raise Unauthorized, 'The ID token was not issued by Google'
        end

        address = claims['email'].to_s.downcase
        vouched = claims['email_verified'] == true &&
                  (address.end_with?('@gmail.com', '@googlemail.com') || claims['hd'].present?)

        { uid: required(claims, 'sub'), info: Info.new(email: claims['email'], email_verified: vouched) }
      end
    end
  end
end
