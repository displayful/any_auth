# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class OAuth2Test < ActiveSupport::TestCase
      TOKEN_URL = 'https://api.hubspot.com/oauth/2026-09/token'

      setup do
        stub_json(:post, 'https://api.hubspot.com/oauth/2026-09/token/introspect',
          active: true, user_id: 41)
      end

      test 'a code is swapped for credentials at the address it was sent back to' do
        stub_json(:post, TOKEN_URL, access_token: 'new', refresh_token: 'refresh')

        auth = hubspot.callback_phase(callback_params, stored_session)

        assert_equal({ 'access_token' => 'new', 'refresh_token' => 'refresh' }, auth.credentials)
        assert_requested :post, TOKEN_URL, body: hash_including(
          'grant_type' => 'authorization_code',
          'code' => 'code',
          'redirect_uri' => CALLBACK_URL
        )
      end

      test 'a callback with another state, or with nothing stored, did not start here' do
        forged = callback_params(state: 'forged')

        assert_raises(InvalidCallback) { hubspot.callback_phase(forged, stored_session) }
        assert_raises(InvalidCallback) { hubspot.callback_phase(callback_params, {}) }
      end

      test 'a callback with no code is not a sign-in' do
        without_code = { 'state' => 's' }

        assert_raises(InvalidCallback) { hubspot.callback_phase(without_code, stored_session) }
      end

      test 'a person who declined at the vendor is AccessDenied, with what the vendor called it' do
        answer = { 'error' => 'access_denied', 'state' => 's' }

        declined = assert_raises(AccessDenied) { hubspot.callback_phase(answer, stored_session) }

        assert_equal 'access_denied', declined.code
      end

      test 'a swap the vendor refuses, or answers without a token, is AccessDenied' do
        stub_request(:post, TOKEN_URL).to_return(status: 400, body: 'invalid_grant')

        assert_raises(AccessDenied) { hubspot.callback_phase(callback_params, stored_session) }

        stub_json(:post, TOKEN_URL, refresh_token: 'refresh')

        assert_raises(AccessDenied) { hubspot.callback_phase(callback_params, stored_session) }
      end

      test "a refusal carries the vendor's reason" do
        stub_json(:post, TOKEN_URL, status: 400, error: 'invalid_grant')

        refused = assert_raises(AccessDenied) do
          hubspot.callback_phase(callback_params, stored_session)
        end

        assert_equal 'invalid_grant', refused.code
      end

      test 'inspecting a strategy, or what came back, shows no secret and no token' do
        stub_json(:post, TOKEN_URL, access_token: 'new')

        auth = hubspot.callback_phase(callback_params, stored_session)

        assert_not_includes hubspot.inspect, 'secret'
        assert_not_includes auth.inspect, 'new'
      end

      test 'a vendor that is down or silent is Unavailable' do
        stub_request(:post, TOKEN_URL).to_return(status: 503)

        assert_raises(Unavailable) { hubspot.callback_phase(callback_params, stored_session) }

        stub_request(:post, TOKEN_URL).to_timeout

        assert_raises(Unavailable) { hubspot.callback_phase(callback_params, stored_session) }
      end

      test 'a vendor gets 5 seconds to connect and 10 to answer' do
        options = hubspot.send(:client).connection.options

        assert_equal 5, options.open_timeout
        assert_equal 10, options.timeout
      end

      test 'a vendor that throttles us is Unavailable, and says when to try again' do
        stub_request(:post, TOKEN_URL).to_return(status: 429, headers: { 'Retry-After' => '30' })

        throttled = assert_raises(Unavailable) { hubspot.refresh('refresh_token' => 'refresh') }

        assert_equal 30, throttled.retry_after
      end

      test 'a wait given as a date is read as seconds from now' do
        later = 2.minutes.from_now.httpdate
        stub_request(:post, TOKEN_URL).to_return(status: 503, headers: { 'Retry-After' => later })

        throttled = assert_raises(Unavailable) { hubspot.refresh('refresh_token' => 'refresh') }

        assert_in_delta 120, throttled.retry_after, 2
      end

      test 'a callback the vendor answers with an outage is Unavailable, not a refusal' do
        answer = { 'error' => 'temporarily_unavailable', 'state' => 's' }

        assert_raises(Unavailable) { hubspot.callback_phase(answer, stored_session) }
      end

      test "a customer's policy refusing the app is AccessDenied, with the vendor's reason" do
        answer = { 'error' => 'unauthorized_client', 'error_description' => 'Not allowed',
                   'state' => 's' }

        refused = assert_raises(AccessDenied) { hubspot.callback_phase(answer, stored_session) }

        assert_equal 'unauthorized_client', refused.code
        assert_equal 'Not allowed', refused.description
      end

      test 'a vendor saying our client is wrong is a ConfigurationError, which raises' do
        stub_json(:post, TOKEN_URL, status: 401, error: 'invalid_client')

        misconfigured = assert_raises(ConfigurationError) do
          hubspot.callback_phase(callback_params, stored_session)
        end

        assert_equal 'invalid_client', misconfigured.code
        assert_kind_of AnyAuth::Error, misconfigured
        assert_not_kind_of AuthenticationError, misconfigured
      end

      test 'a refusal from the oauth2 gem itself carries no vendor code' do
        refused = assert_raises(AccessDenied) { hubspot.refresh({}) }

        assert_nil refused.code
      end

      test 'the client is named in the request body, unless the strategy asks for another scheme' do
        stub_json(:post, TOKEN_URL, access_token: 'new')
        strategy_class = Class.new(Hubspot) do
          def client_options
            super.merge(auth_scheme: :basic_auth)
          end
        end

        basic = strategy_class.new(client_id: 'app', client_secret: 'secret', provider: 'basic')

        hubspot.callback_phase(callback_params, stored_session)
        basic.callback_phase(callback_params, stored_session)

        assert_requested :post, TOKEN_URL, body: hash_including('client_secret' => 'secret')
        assert_requested :post, TOKEN_URL, headers: { 'Authorization' => /\ABasic / }
      end

      test 'a strategy with no client id is an error, not a trip to the vendor' do
        error = assert_raises(ArgumentError) do
          Hubspot.new.request_phase(redirect_uri: CALLBACK_URL)
        end

        assert_includes error.message, 'client_id'
      end

      test 'no challenge is sent when PKCE is switched off' do
        without = Hubspot.new(client_id: 'app', client_secret: 'secret', pkce: false)
        request = without.request_phase(redirect_uri: CALLBACK_URL)

        assert_nil query_of(request.url)['code_challenge']
        assert_nil request.session['code_verifier']
      end

      test 'leaving sends a PKCE challenge and the swap sends its verifier' do
        stub_json(:post, TOKEN_URL, access_token: 'new')
        hubspot = Hubspot.new(client_id: 'app', client_secret: 'secret')
        request = hubspot.request_phase(redirect_uri: CALLBACK_URL)
        sent = query_of(request.url)
        verifier = request.session['code_verifier']

        hubspot.callback_phase(callback_params(state: sent['state']), request.session)

        assert_equal 'S256', sent['code_challenge_method']
        assert_equal 43, verifier.length
        assert_equal challenge_for(verifier), sent['code_challenge']
        assert_requested :post, TOKEN_URL, body: hash_including('code_verifier' => verifier)
      end

      private

      def hubspot
        Hubspot.new(client_id: 'app', client_secret: 'secret')
      end
    end
  end
end
