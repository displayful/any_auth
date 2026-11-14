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
        raise Unauthorized, 'The ID token was not issued by Google' unless issued_by_google?(claims)

        { uid: required(claims, 'sub'), info: info_from(claims) }
      end

      def info_from(claims)
        Info.new(name: claims['name'], email: claims['email'], email_verified: vouched_for?(claims),
          image: claims['picture'])
      end

      def issued_by_google?(claims)
        claims['iss'].in?(%w[https://accounts.google.com accounts.google.com])
      end

      def vouched_for?(claims)
        claims['email_verified'] == true && hosted_by_google?(claims)
      end

      def hosted_by_google?(claims)
        gmail = claims['email'].to_s.downcase.end_with?('@gmail.com', '@googlemail.com')

        gmail || claims['hd'].present?
      end
    end
  end
end
