require 'test_helper'

module AnyAuth
  module Strategies
    class OAuthTest < ActiveSupport::TestCase
      TOKEN_URL = 'https://api.hubapi.com/oauth/v1/token'.freeze
      HELD = { 'state' => 's', 'redirect_uri' => 'https://tavle.test/callback' }.freeze

      setup do
        stub_json(:get, 'https://api.hubapi.com/oauth/v1/access-tokens/ny', user_id: 41)
      end

      test 'a code is swapped for credentials at the address it was sent back to' do
        stub_json(:post, TOKEN_URL, access_token: 'ny', refresh_token: 'igen', token_type: 'bearer')

        auth = come_home('code' => 'kode', 'state' => 's')

        assert_equal({ 'access_token' => 'ny', 'refresh_token' => 'igen' }, auth.credentials)
        assert_requested :post, TOKEN_URL, body: hash_including('grant_type' => 'authorization_code',
          'code' => 'kode', 'redirect_uri' => 'https://tavle.test/callback')
      end

      test 'a callback with another state, or with nothing held, did not start here' do
        assert_raises(InvalidCallback) { come_home('code' => 'kode', 'state' => 'forged') }
        assert_raises(InvalidCallback) { hubspot.callback_phase({ 'code' => 'kode', 'state' => 's' }, nil) }
      end

      test 'a callback with no code is not a sign-in' do
        assert_raises(InvalidCallback) { come_home('state' => 's') }
      end

      test 'a person who declined at the vendor is Declined, with what the vendor called it' do
        declined = assert_raises(Declined) { come_home('error' => 'access_denied', 'state' => 's') }

        assert_equal 'access_denied', declined.code
      end

      test 'a swap the vendor refuses, or answers without a token, is Unauthorized' do
        stub_request(:post, TOKEN_URL).to_return(status: 400, body: 'invalid_grant')

        assert_raises(Unauthorized) { come_home('code' => 'kode', 'state' => 's') }

        stub_json(:post, TOKEN_URL, refresh_token: 'igen')

        assert_raises(Unauthorized) { come_home('code' => 'kode', 'state' => 's') }
      end

      test 'a vendor that is down or silent is Unavailable' do
        stub_request(:post, TOKEN_URL).to_return(status: 503)

        assert_raises(Unavailable) { come_home('code' => 'kode', 'state' => 's') }

        stub_request(:post, TOKEN_URL).to_timeout

        assert_raises(Unavailable) { come_home('code' => 'kode', 'state' => 's') }
      end

      test 'a vendor that throttles us is RateLimited' do
        stub_request(:post, TOKEN_URL).to_return(status: 429)

        assert_raises(RateLimited) { hubspot.refresh!('refresh_token' => 'igen') }
      end

      private

      def hubspot
        Hubspot.new(client_id: 'app', client_secret: 'tys')
      end

      def come_home(params)
        hubspot.callback_phase(params, HELD)
      end
    end
  end
end
