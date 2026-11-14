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
        session = { 'state' => SecureRandom.hex(24), 'redirect_uri' => redirect_uri }
        params = params.merge(pkce_params(session)) if pkce?
        url = client.auth_code.authorize_url(
          **authorize_params, **params, redirect_uri:, state: session['state']
        )

        Request.new(url:, session:)
      end

      def callback_phase(params, session)
        session = session.to_h
        verify(params, session)
        token = exchange(params['code'], session)

        Auth.new(provider:, credentials: credentials_from(token), **identity(token, session))
      end

      def expired?(credentials)
        value = credentials.to_h.stringify_keys['expires_at']
        return false if value.blank?

        time = parse_time(value)
        time.nil? || time.before?(2.minutes.from_now)
      end

      def refresh(credentials)
        return credentials unless expired?(credentials)

        refresh!(credentials)
      end

      def refresh!(credentials)
        credentials = credentials.to_h.stringify_keys
        token = with_error_handling do
          OAuth2::AccessToken.from_hash(client, credentials).refresh(parse: :json)
        end

        credentials.except('expires_at').merge(credentials_from(token))
      end

      private

      def authorize_params
        authorize_options.index_with { public_send(it) }.compact_blank
      end

      def pkce_params(session)
        pair = PKCE.pair
        session['code_verifier'] = pair.verifier

        { code_challenge: pair.challenge, code_challenge_method: 'S256' }
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

      def parse_time(value)
        case value
        when Numeric then Time.at(value)
        when String then value.to_time(:utc)
        end
      rescue ArgumentError
        nil
      end

      def client
        OAuth2::Client.new(client_id, client_secret, client_options) do
          it.request :url_encoded
          it.response :raise_error
        end
      end

      def get(token, path)
        body = with_error_handling { token.get(path).parsed }
        raise Unavailable, "#{provider} returned an unreadable response" unless body.is_a?(Hash)

        body
      end

      def with_error_handling
        yield
      rescue OAuth2::Error => e
        raise Unauthorized, "#{provider} returned #{e.code || 'no token'}", cause: nil
      rescue Faraday::Error, JSON::ParserError => e
        error_class = error_class_for(e.try(:response_status))
        raise error_class, "#{provider} request failed (#{e.class.name.demodulize})", cause: nil
      end

      def error_class_for(status)
        case status
        when 400, 401, 403 then Unauthorized
        when 429 then RateLimited
        else Unavailable
        end
      end
    end
  end
end
