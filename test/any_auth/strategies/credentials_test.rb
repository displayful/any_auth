require 'test_helper'

module AnyAuth
  module Strategies
    class CredentialsTest < ActiveSupport::TestCase
      TOKEN_URL = 'https://api.hubapi.com/oauth/v1/token'.freeze

      test 'credentials still good, or that never expire, are answered as they are' do
        good = { 'access_token' => 'adgang', 'expires_at' => 1.hour.from_now.utc.iso8601 }
        lasting = { 'access_token' => 'adgang' }
        pasted = { 'username' => 'api', 'password' => 'hemmeligt' }

        assert_equal good, hubspot.refresh(good)
        assert_equal lasting, hubspot.refresh(lasting)
        assert_equal pasted, Adversus.new.refresh(pasted)
        assert_not_requested :post, TOKEN_URL
      end

      test 'credentials about to expire are renewed, and keep a refresh token not replaced' do
        stub_json(:post, TOKEN_URL, access_token: 'nyere', expires_in: 1800)

        renewed = hubspot.refresh(expiring(1.minute.from_now))

        assert_equal 'nyere', renewed['access_token']
        assert_equal 'igen', renewed['refresh_token']
        assert_operator Time.iso8601(renewed['expires_at']), :>, 20.minutes.from_now
        assert_requested :post, TOKEN_URL, body: hash_including(
          'grant_type' => 'refresh_token',
          'refresh_token' => 'igen'
        )
      end

      test 'a renewal that names no new expiry forgets the old one' do
        stub_json(:post, TOKEN_URL, access_token: 'nyere')

        renewed = hubspot.refresh(expiring(1.minute.ago))

        assert_not hubspot.expired?(renewed)
      end

      test 'a renewal the vendor refuses, or that has no refresh token to offer, is Unauthorized' do
        stub_request(:post, TOKEN_URL).to_return(status: 400, body: 'invalid_grant')

        assert_raises(Unauthorized) { hubspot.refresh!(expiring(1.minute.ago)) }
        assert_raises(Unauthorized) { hubspot.refresh!({}) }
      end

      test 'expiry is read whether it was stored as text, as a number or under symbol keys' do
        assert hubspot.expired?('expires_at' => 1.minute.from_now.to_i)
        assert hubspot.expired?(expires_at: 1.minute.from_now.utc.iso8601)
        assert hubspot.expired?('expires_at' => 'not a time')
        assert_not hubspot.expired?('expires_at' => 3.minutes.from_now.to_i)
      end

      private

      def hubspot
        Hubspot.new(client_id: 'app', client_secret: 'tys')
      end

      def expiring(time)
        { 'access_token' => 'gammel', 'refresh_token' => 'igen', 'expires_at' => time.utc.iso8601 }
      end
    end
  end
end
