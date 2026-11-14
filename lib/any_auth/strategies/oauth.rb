# frozen_string_literal: true

module AnyAuth
  module Strategies
    class OAuth < Base
      class_attribute :authorize_options, default: [], instance_writer: false
      class_attribute :pkce, default: false

      attr_accessor :client_id, :client_secret

      def self.authorize_option(*names)
        self.authorize_options += names
        attr_accessor(*names)
      end

      authorize_option :scope

      def request_phase(redirect_uri:, **params)
        state = SecureRandom.hex(24)
        session = { 'state' => state, 'redirect_uri' => redirect_uri }

        if pkce?
          pkce = PKCE.pair
          session['code_verifier'] = pkce.verifier
          params = params.merge(code_challenge: pkce.challenge, code_challenge_method: 'S256')
        end

        url = client.auth_code.authorize_url(**authorize_params, **params, redirect_uri:, state:)

        Request.new(url:, session:)
      end

      def callback_phase(params, session)
        verify(params, session)
        token = exchange(params['code'], session)

        Auth.new(provider:, credentials: credentials_from(token), **identity(token, session))
      end

      def expired?(credentials)
        expires_at = credentials['expires_at']&.to_time

        expires_at.present? && expires_at.before?(2.minutes.from_now)
      end

      def refresh(credentials)
        return credentials unless expired?(credentials)

        refresh!(credentials)
      end

      def refresh!(credentials)
        token = with_error_handling { OAuth2::AccessToken.from_hash(client, credentials).refresh }

        credentials.except('expires_at').merge(credentials_from(token))
      end

      private

      def authorize_params
        authorize_options.index_with { public_send(it) }.compact_blank
      end

      def verify(params, session)
        raise InvalidCallback, 'No sign-in in progress' if session['redirect_uri'].blank?
        raise InvalidCallback, 'Invalid state' unless valid_state?(params, session)
        raise Declined, params['error'] if params['error'].present?
        raise InvalidCallback, 'Missing code' if params['code'].blank?
      end

      def valid_state?(params, session)
        secure_compare(session['state'], params['state'])
      end

      def exchange(code, session, **params)
        params = params.merge(
          redirect_uri: session['redirect_uri'],
          code_verifier: session['code_verifier'],
        )

        with_error_handling { client.auth_code.get_token(code, params.compact) }
      end

      def identity(_token, _session)
        {}
      end

      def credentials_from(token)
        raise Unauthorized, "#{provider} returned no access token" if token.token.blank?

        {
          'access_token' => token.token,
          'refresh_token' => token.refresh_token,
          'expires_at' => (Time.at(token.expires_at).utc.iso8601 if token.expires_at),
        }.compact
      end

      def client
        OAuth2::Client.new(client_id, client_secret, **default_client_options, **client_options)
      end

      def default_client_options
        { auth_scheme: :request_body }
      end

      def get(token, path)
        body = with_error_handling { token.get(path).parsed }
        raise Unavailable, "#{provider} returned an unreadable response" unless body.is_a?(Hash)

        body
      end

      def with_error_handling
        yield
      rescue OAuth2::Error => e
        raise vendor_error(e), cause: nil
      rescue Faraday::Error, JSON::ParserError => e
        raise Unavailable, "#{provider} request failed (#{e.class.name.demodulize})", cause: nil
      end

      def vendor_error(error)
        status = error.response.try(:status)
        message = "#{provider} returned #{error.code || status || 'no token'}"

        error_class_for(status).new(message, code: error.code)
      end

      def error_class_for(status)
        case status
        when nil, 400, 401, 403 then Unauthorized
        when 429 then RateLimited
        else Unavailable
        end
      end
    end
  end
end
