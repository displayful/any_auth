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
        expires_at = expiry_in(credentials.to_h.stringify_keys)

        expires_at.present? && expires_at.before?(2.minutes.from_now)
      end

      def refresh(credentials)
        expired?(credentials) ? refresh!(credentials) : credentials
      end

      def refresh!(credentials)
        credentials = credentials.to_h.stringify_keys
        token = asking_the_vendor do
          OAuth2::AccessToken.from_hash(client, credentials).refresh(parse: :json)
        end

        credentials.except('expires_at').merge(credentials_from(token))
      end

      private

      def authorize_params
        authorize_options.index_with { public_send(it) }.compact_blank
      end

      def verify(params, session)
        started = session['redirect_uri'].present?
        echoed = same?(session['state'], params['state'])

        raise InvalidCallback, "No sign-in at #{provider} is under way" unless started
        raise InvalidCallback, "#{provider} did not send back the state we sent" unless echoed
        raise Declined, params['error'] if params['error'].present?
        raise InvalidCallback, "#{provider} sent back no code" if params['code'].blank?
      end

      def pkce_params(session)
        pair = PKCE.pair
        session['code_verifier'] = pair.verifier

        { code_challenge: pair.challenge, code_challenge_method: 'S256' }
      end

      def exchange(code, session, **params)
        params = params.merge(
          redirect_uri: session['redirect_uri'],
          code_verifier: session['code_verifier'],
        )

        asking_the_vendor { client.auth_code.get_token(code, params.compact) }
      end

      def identity(_token, _session)
        {}
      end

      def asked_with(token, path)
        answer = asking_the_vendor { token.get(path).parsed }
        return answer if answer.is_a?(Hash)

        raise Unavailable, "#{provider} answered with something we cannot read"
      end

      def credentials_from(token)
        raise Unauthorized, "#{provider} sent no access token" if token.token.blank?

        {
          'access_token' => token.token,
          'refresh_token' => token.refresh_token,
          'expires_at' => (Time.at(token.expires_at).utc.iso8601 if token.expires_at),
        }.compact
      end

      def expiry_in(credentials)
        case expires_at = credentials['expires_at']
        when Numeric then Time.at(expires_at)
        when String then expires_at.to_time(:utc) || Time.at(0)
        end
      rescue ArgumentError
        Time.at(0)
      end

      def client
        OAuth2::Client.new(client_id, client_secret, client_options) do
          it.request :url_encoded
          it.response :raise_error
        end
      end

      def asking_the_vendor
        yield
      rescue OAuth2::Error => e
        raise Unauthorized, "#{provider} refused us (#{e.code || 'no token'})", cause: nil
      rescue Faraday::Error, JSON::ParserError => e
        error = error_for(e.try(:response_status))
        raise error, "#{provider} could not be asked (#{e.class.name.demodulize})", cause: nil
      end

      def error_for(status)
        case status
        when 400, 401, 403 then Unauthorized
        when 429 then RateLimited
        else Unavailable
        end
      end
    end
  end
end
