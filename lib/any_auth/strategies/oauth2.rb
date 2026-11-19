# frozen_string_literal: true

module AnyAuth
  module Strategies
    class OAuth2 < Base
      class_attribute :authorize_options, default: [], instance_writer: false
      class_attribute :pkce, default: true

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

      def refresh(credentials)
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

        params = access_token.params
        # The refresh token's lifetime: the IETF draft calls it refresh_token_timeout; GitHub,
        # Google and Shopify say refresh_token_expires_in.
        lifetime = params['refresh_token_timeout'] || params['refresh_token_expires_in']
        refresh_token_expires_at = Time.now.to_i + lifetime.to_i if lifetime

        {
          'access_token' => access_token.token,
          'token_type' => params['token_type'],
          'refresh_token' => access_token.refresh_token,
          'expires_at' => access_token.expires_at,
          'refresh_token_expires_at' => refresh_token_expires_at,
          'scope' => params['scope'],
        }.compact
      end

      def client
        ::OAuth2::Client.new(client_id, client_secret, **default_client_options, **client_options)
      end

      # Faraday waits a minute by default; a sign-in or refresh shouldn't hang that long.
      def default_client_options
        { auth_scheme: :request_body, connection_opts: { request: { open_timeout: 5, timeout: 10 } } }
      end

      def get(access_token, path)
        parsed { access_token.get(path, snaky: false) }
      end

      def parsed
        body = with_error_handling { yield.parsed }
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
