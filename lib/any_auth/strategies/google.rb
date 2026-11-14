# frozen_string_literal: true

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
        raise Unauthorized, 'Invalid issuer' unless issued_by_google?(claims)

        { uid: fetch_claim(claims, 'sub'), info: info_from(claims) }
      end

      def info_from(claims)
        Info.new(
          name: claims['name'],
          email: claims['email'],
          email_verified: email_verified?(claims),
          image: claims['picture'],
        )
      end

      def issued_by_google?(claims)
        claims['iss'].in?(%w[https://accounts.google.com accounts.google.com])
      end

      def email_verified?(claims)
        claims['email_verified'] == true && google_hosted?(claims)
      end

      def google_hosted?(claims)
        claims['hd'].present? ||
          claims['email'].to_s.downcase.end_with?('@gmail.com', '@googlemail.com')
      end
    end
  end
end
