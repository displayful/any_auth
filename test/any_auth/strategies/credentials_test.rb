# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class CredentialsTest < ActiveSupport::TestCase
      TOKEN_URL = 'https://api.hubapi.com/oauth/v1/token'

      test 'credentials still good, or that never expire, are answered as they are' do
        good = { 'access_token' => 'access', 'expires_at' => 1.hour.from_now.utc.iso8601 }
        lasting = { 'access_token' => 'access' }
        pasted = { 'username' => 'api', 'password' => 'password' }

        assert_equal good, hubspot.refresh(good)
        assert_equal lasting, hubspot.refresh(lasting)
        assert_equal pasted, Adversus.new.refresh(pasted)
        assert_not_requested :post, TOKEN_URL
      end

      test 'credentials about to expire are renewed, and keep a refresh token not replaced' do
        stub_json(:post, TOKEN_URL, access_token: 'newer', expires_in: 1800)

        renewed = hubspot.refresh(expiring(1.minute.from_now))

        assert_equal 'newer', renewed['access_token']
        assert_equal 'refresh', renewed['refresh_token']
        assert_operator Time.iso8601(renewed['expires_at']), :>, 20.minutes.from_now
        assert_requested :post, TOKEN_URL, body: hash_including(
          'grant_type' => 'refresh_token',
          'refresh_token' => 'refresh'
        )
      end

      test 'a renewal that names no new expiry forgets the old one' do
        stub_json(:post, TOKEN_URL, access_token: 'newer')

        renewed = hubspot.refresh(expiring(1.minute.ago))

        assert_not hubspot.expired?(renewed)
      end

      test 'a renewal the vendor refuses, or that has no refresh token to offer, is Unauthorized' do
        stub_request(:post, TOKEN_URL).to_return(status: 400, body: 'invalid_grant')

        assert_raises(Unauthorized) { hubspot.refresh!(expiring(1.minute.ago)) }
        assert_raises(Unauthorized) { hubspot.refresh!({}) }
      end

      test 'credentials count as expired two minutes early' do
        assert hubspot.expired?(expiring(1.minute.from_now))
        assert_not hubspot.expired?(expiring(3.minutes.from_now))
      end

      private

      def hubspot
        Hubspot.new(client_id: 'app', client_secret: 'secret')
      end

      def expiring(time)
        { 'access_token' => 'old', 'refresh_token' => 'refresh', 'expires_at' => time.utc.iso8601 }
      end
    end
  end
end
