module AnyAuth
  module Strategies
    class OAuth < Base
      class_attribute :authorize_options, default: [], instance_writer: false

      attr_accessor :client_id, :client_secret

      def self.authorize_option(*names)
        self.authorize_options += names
        attr_accessor(*names)
      end

      authorize_option :scope

      def request_phase(redirect_uri:, **params)
        state = SecureRandom.hex(24)
        url = client.auth_code.authorize_url(redirect_uri:, state:, **authorize_params, **params)

        Request.new(url:, session: { 'state' => state, 'redirect_uri' => redirect_uri })
      end

      def callback_phase(params, session)
        session = session.to_h
        verify(params, session)
        token = exchange(params['code'], session)

        Auth.new(provider:, credentials: credentials_from(token), **identity(token, session))
      end

      def expired?(credentials)
        expires_at = credentials['expires_at'].to_s.to_time

        expires_at.present? && expires_at.before?(2.minutes.from_now)
      end

      def refresh(credentials)
        expired?(credentials) ? refresh!(credentials) : credentials
      end

      def refresh!(credentials)
        token = asking_the_vendor { OAuth2::AccessToken.from_hash(client, credentials).refresh(parse: :json) }

        credentials.merge(credentials_from(token))
      end

      private

      def authorize_params
        authorize_options.index_with { public_send(it) }.compact_blank
      end

      def verify(params, session)
        raise InvalidCallback, "No sign-in at #{provider} is under way" if session['redirect_uri'].blank?
        raise InvalidCallback, "#{provider} did not send back the state we sent" unless state_echoed?(params, session)
        raise Declined, params['error'] if params['error'].present?
        raise InvalidCallback, "#{provider} sent back no code" if params['code'].blank?
      end

      def state_echoed?(params, session)
        same?(session['state'], params['state'])
      end

      def exchange(code, session, **params)
        asking_the_vendor { client.auth_code.get_token(code, { redirect_uri: session['redirect_uri'], **params }) }
      end

      def identity(_token, _session)
        {}
      end

      def asked_with(token, path)
        asking_the_vendor { token.get(path).parsed }
      end

      def credentials_from(token)
        {
          'access_token' => token.token,
          'refresh_token' => token.refresh_token,
          'expires_at' => (Time.at(token.expires_at).utc.iso8601 if token.expires_at),
        }.compact
      end

      def client
        @client ||= OAuth2::Client.new(client_id, client_secret, client_options) do
          it.request :url_encoded
          it.response :raise_error
        end
      end

      def asking_the_vendor
        yield
      rescue OAuth2::Error => e
        raise Unauthorized, "#{provider} refused us: #{e.message}"
      rescue Faraday::Error, JSON::ParserError => e
        case e.try(:response_status)
        when 400, 401, 403 then raise Unauthorized, "#{provider} refused us (#{e.response_status})"
        when 429 then raise RateLimited, "#{provider} asked us to slow down"
        else raise Unavailable, "#{provider} could not be reached (#{e.class.name.demodulize})"
        end
      end
    end
  end
end
