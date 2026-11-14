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
        }
      end

      private

      def info_from(claims)
        Info.new(
          name: claims['name'],
          email: claims['email'],
          email_verified: email_verified?(claims),
          image: claims['picture'],
        )
      end

      def valid_issuer?(claims)
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
