# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class OAuthTest < ActiveSupport::TestCase
      TOKEN_URL = 'https://api.hubapi.com/oauth/v1/token'

      setup do
        stub_json(:get, 'https://api.hubapi.com/oauth/v1/access-tokens/new', user_id: 41)
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

      test 'a person who declined at the vendor is Declined, with what the vendor called it' do
        answer = { 'error' => 'access_denied', 'state' => 's' }

        declined = assert_raises(Declined) { hubspot.callback_phase(answer, stored_session) }

        assert_equal 'access_denied', declined.code
      end

      test 'a swap the vendor refuses, or answers without a token, is Unauthorized' do
        stub_request(:post, TOKEN_URL).to_return(status: 400, body: 'invalid_grant')

        assert_raises(Unauthorized) { hubspot.callback_phase(callback_params, stored_session) }

        stub_json(:post, TOKEN_URL, refresh_token: 'refresh')

        assert_raises(Unauthorized) { hubspot.callback_phase(callback_params, stored_session) }
      end

      test "a refusal carries the vendor's reason" do
        stub_json(:post, TOKEN_URL, status: 400, error: 'invalid_grant')

        refused = assert_raises(Unauthorized) do
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

      test 'a vendor that throttles us is RateLimited' do
        stub_request(:post, TOKEN_URL).to_return(status: 429)

        assert_raises(RateLimited) { hubspot.refresh!('refresh_token' => 'refresh') }
      end

      test 'no challenge is sent unless PKCE is switched on' do
        request = hubspot.request_phase(redirect_uri: CALLBACK_URL)

        assert_nil query_of(request.url)['code_challenge']
        assert_nil request.session['code_verifier']
      end

      test 'with PKCE switched on, leaving sends a challenge and the swap sends its verifier' do
        stub_json(:post, TOKEN_URL, access_token: 'new')
        hubspot = Hubspot.new(client_id: 'app', client_secret: 'secret', pkce: true)
        request = hubspot.request_phase(redirect_uri: CALLBACK_URL)
        sent = query_of(request.url)
        verifier = request.session['code_verifier']

        hubspot.callback_phase(callback_params(state: sent['state']), request.session)

        assert_equal 'S256', sent['code_challenge_method']
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
