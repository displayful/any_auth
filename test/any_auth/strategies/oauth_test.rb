require 'test_helper'

module AnyAuth
  module Strategies
    class OAuthTest < ActiveSupport::TestCase
      HELD = { 'state' => 's', 'redirect_uri' => 'https://tavle.example/callback' }.freeze

      test 'a code is swapped for credentials at the address it was sent back to' do
        swap = stub_request(:post, 'https://api.hubapi.com/oauth/v1/token')
               .with(body: hash_including('grant_type' => 'authorization_code', 'code' => 'kode',
                 'redirect_uri' => 'https://tavle.example/callback'))
               .to_return(headers: { 'Content-Type' => 'application/json' },
                 body: { access_token: 'ny', refresh_token: 'igen', token_type: 'bearer' }.to_json)

        auth = hubspot.callback_phase({ 'code' => 'kode', 'state' => 's' }, HELD)

        assert_requested swap
        assert_equal({ 'access_token' => 'ny', 'refresh_token' => 'igen' }, auth.credentials)
      end

      test 'a swap the vendor refuses is denied, and a vendor that cannot answer is unavailable' do
        stub_request(:post, 'https://api.hubapi.com/oauth/v1/token').to_return(status: 400, body: 'invalid_grant')

        assert_raises(Unauthorized) { hubspot.callback_phase({ 'code' => 'kode', 'state' => 's' }, HELD) }

        stub_request(:post, 'https://api.hubapi.com/oauth/v1/token').to_return(status: 503)

        assert_raises(Unavailable) { hubspot.callback_phase({ 'code' => 'kode', 'state' => 's' }, HELD) }

        stub_request(:post, 'https://api.hubapi.com/oauth/v1/token').to_timeout

        assert_raises(Unavailable) { hubspot.callback_phase({ 'code' => 'kode', 'state' => 's' }, HELD) }
      end

      test 'a refresh the vendor refuses, throttles or cannot answer says which' do
        held = { 'access_token' => 'gammel', 'refresh_token' => 'igen' }
        token = stub_request(:post, 'https://api.hubapi.com/oauth/v1/token')

        token.to_return(status: 400, body: 'invalid_grant')

        assert_raises(Unauthorized) { hubspot.refresh!(held) }
        assert_raises(Unauthorized) { hubspot.refresh!({}) }

        token.to_return(status: 429)

        assert_raises(RateLimited) { hubspot.refresh!(held) }

        token.to_return(status: 502, headers: { 'Content-Type' => 'text/html' }, body: '<html>Bad gateway</html>')

        assert_raises(Unavailable) { hubspot.refresh!(held) }
      end

      test 'refreshing answers the renewed tokens' do
        stub_request(:post, 'https://api.hubapi.com/oauth/v1/token')
          .with(body: hash_including('grant_type' => 'refresh_token', 'refresh_token' => 'igen'))
          .to_return(headers: { 'Content-Type' => 'application/json' },
            body: { access_token: 'nyere', expires_in: 1800 }.to_json)

        renewed = hubspot.refresh!('access_token' => 'gammel', 'refresh_token' => 'igen')

        assert_equal 'nyere', renewed['access_token']
        assert_operator Time.iso8601(renewed['expires_at']), :>, 20.minutes.from_now
      end

      test 'a callback with another state, or none held, did not start here' do
        assert_raises(InvalidCallback) { hubspot.callback_phase({ 'code' => 'kode', 'state' => 'forged' }, HELD) }
        assert_raises(InvalidCallback) { hubspot.callback_phase({ 'code' => 'kode' }, HELD.except('state')) }
        assert_raises(InvalidCallback) { hubspot.callback_phase({ 'code' => 'kode' }, nil) }
      end

      test 'Relatel echoes no state back, and is swapped all the same' do
        swap = stub_request(:post, 'https://app.relatel.dk/api/v2/token')
               .to_return(headers: { 'Content-Type' => 'application/json' }, body: { access_token: 'ny' }.to_json)

        Relatel.new(client_id: 'app', client_secret: 'tys').callback_phase({ 'code' => 'kode' }, HELD)

        assert_requested swap
      end

      test 'a vendor that answers with an error declined, once the callback is known to be ours' do
        refusal = { 'error' => 'invalid_scope', 'state' => 's' }

        assert_equal 'invalid_scope', assert_raises(Declined) { hubspot.callback_phase(refusal, HELD) }.code
        assert_raises(InvalidCallback) { hubspot.callback_phase(refusal.merge('state' => 'forged'), HELD) }
        assert_raises(InvalidCallback) { hubspot.callback_phase({ 'state' => 's' }, HELD) }
      end

      private

      def hubspot
        Hubspot.new(client_id: 'app', client_secret: 'tys')
      end
    end
  end
end
