module AnyAuth
  module Strategies
    class Tavle < OAuth
      self.pkce = true

      def client_options
        {
          site: 'https://tavle.co',
          authorize_url: '/oauth/authorize',
          token_url: '/oauth/token',
          auth_scheme: :request_body,
        }
      end

      private

      def identity(token, _session)
        userinfo = asked_with(token, '/oauth/userinfo')
        raise Unauthorized, 'tavle named nobody for this token' if userinfo['sub'].blank?

        { uid: userinfo['sub'].to_s, info: info_from(userinfo), raw: userinfo }
      end

      def info_from(userinfo)
        Info.new(
          name: userinfo['name'],
          email: userinfo['email'],
          email_verified: userinfo['email_verified'] == true,
        )
      end
    end
  end
end
