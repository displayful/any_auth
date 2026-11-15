# frozen_string_literal: true

module AnyAuth
  module Strategies
    class OAuth2 < Base
      class_attribute :authorize_options, default: [], instance_writer: false
      class_attribute :pkce, default: false

      attr_accessor :client_id, :client_secret

      def self.authorize_option(*names)
        self.authorize_options += names
        attr_accessor(*names)
      end

      authorize_option :scope

      def request_phase(redirect_uri:, **params)
        raise ArgumentError, "#{provider} needs a client_id" if client_id.blank?

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
        access_token = fetch_access_token(params['code'], session)
        credentials = credentials_from(access_token)

        Auth.new(provider:, credentials:, **identity(access_token, session))
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
        access_token = with_error_handling do
          ::OAuth2::AccessToken.from_hash(client, credentials).refresh
        end

        credentials.except('expires_at').merge(credentials_from(access_token))
      end

      private

      def authorize_params
        authorize_options.index_with { public_send(it) }.compact_blank
      end

      def verify(params, session)
        raise InvalidCallback, 'No sign-in in progress' if session['redirect_uri'].blank?
        raise InvalidCallback, 'Invalid state' unless valid_state?(params, session)
        raise error_from(nil, params) if error_code(params).present?
        raise InvalidCallback, 'Missing code' if params['code'].blank?
      end

      def valid_state?(params, session)
        secure_compare(session['state'], params['state'])
      end

      def fetch_access_token(code, session, **params)
        params = params.merge(
          redirect_uri: session['redirect_uri'],
          code_verifier: session['code_verifier'],
        )

        with_error_handling { client.auth_code.get_token(code, params.compact) }
      end

      def identity(_token, _session)
        {}
      end

      def credentials_from(access_token)
        raise AccessDenied, "#{provider} returned no access token" if access_token.token.blank?

        {
          'access_token' => access_token.token,
          'refresh_token' => access_token.refresh_token,
          'expires_at' => (Time.at(access_token.expires_at).utc.iso8601 if access_token.expires_at),
        }.compact
      end

      def client
        ::OAuth2::Client.new(client_id, client_secret, **default_client_options, **client_options)
      end

      def default_client_options
        { auth_scheme: :request_body }
      end

      def get(access_token, path)
        body = with_error_handling { access_token.get(path, snaky: false).parsed }
        raise Unavailable, "#{provider} returned an unreadable response" unless body.is_a?(Hash)

        body
      end

      def with_error_handling
        yield
      rescue ::OAuth2::Error => e
        raise vendor_error(e), cause: nil
      rescue Faraday::Error, JSON::ParserError => e
        raise Unavailable, "#{provider} request failed (#{e.class.name.demodulize})", cause: nil
      end

      def vendor_error(error)
        response = error.response
        return error_from(nil, {}) unless response.is_a?(::OAuth2::Response)

        body = response.parsed
        body = {} unless body.is_a?(Hash)

        error_from(response.status, body, response.headers)
      end
    end
  end
end
