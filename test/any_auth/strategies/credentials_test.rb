# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class CredentialsTest < ActiveSupport::TestCase
      TOKEN_URL = 'https://api.hubspot.com/oauth/2026-09/token'
      TAVLE_TOKEN_URL = 'https://tavle.co/oauth/token'

      test 'credentials that cannot be renewed are answered as they are' do
        pasted = { 'username' => 'api', 'password' => 'password' }

        assert_equal pasted, Adversus.new.refresh(pasted)
      end

      test 'a refresh asks the vendor, and keeps a refresh token not replaced' do
        stub_json(:post, TOKEN_URL, access_token: 'newer', expires_in: 1800)

        renewed = hubspot.refresh(stored)

        assert_equal 'newer', renewed['access_token']
        assert_equal 'refresh', renewed['refresh_token']
        assert_in_delta 30.minutes.from_now.to_i, renewed['expires_at'], 5
        assert_requested :post, TOKEN_URL, body: hash_including(
          'grant_type' => 'refresh_token',
          'refresh_token' => 'refresh'
        )
      end

      test 'a renewal that names no new expiry forgets the old one' do
        stub_json(:post, TOKEN_URL, access_token: 'newer')

        renewed = hubspot.refresh(stored)

        assert_nil renewed['expires_at']
      end

      test 'an expiry stored as ISO 8601 by 0.1.0 still refreshes' do
        stub_json(:post, TOKEN_URL, access_token: 'newer', expires_in: 1800)

        renewed = hubspot.refresh(stored.merge('expires_at' => 1.minute.ago.utc.iso8601))

        assert_kind_of Integer, renewed['expires_at']
      end

      test 'a renewal the vendor refuses, or that has no refresh token to offer, is AccessDenied' do
        stub_request(:post, TOKEN_URL).to_return(status: 400, body: 'invalid_grant')

        assert_raises(AccessDenied) { hubspot.refresh(stored) }
        assert_raises(AccessDenied) { hubspot.refresh({}) }
      end

      test 'credentials carry the token type and the granted scope' do
        stub_json(:post, TAVLE_TOKEN_URL, access_token: 'newer', token_type: 'Bearer',
          scope: 'boards:read')

        renewed = tavle.refresh(stored)

        assert_equal 'Bearer', renewed['token_type']
        assert_equal 'boards:read', renewed['scope']
      end

      test 'a refresh token expiry under either name becomes a time' do
        stub_json(:post, TAVLE_TOKEN_URL, access_token: 'newer', refresh_token_timeout: 2_592_000)
        timeout = tavle.refresh(stored)
        stub_json(:post, TAVLE_TOKEN_URL, access_token: 'newer',
          refresh_token_expires_in: 2_592_000)
        expires_in = tavle.refresh(stored)

        assert_in_delta 30.days.from_now.to_i, timeout['refresh_token_expires_at'], 5
        assert_in_delta 30.days.from_now.to_i, expires_in['refresh_token_expires_at'], 5
      end

      test 'a refresh token expiry the vendor does not send again is kept' do
        stub_json(:post, TAVLE_TOKEN_URL, access_token: 'newer')

        renewed = tavle.refresh(stored.merge('refresh_token_expires_at' => 1_800_000_000))

        assert_equal 1_800_000_000, renewed['refresh_token_expires_at']
      end

      private

      def hubspot
        Hubspot.new(client_id: 'app', client_secret: 'secret')
      end

      def tavle
        Tavle.new(client_id: 'app', client_secret: 'secret')
      end

      def stored
        { 'access_token' => 'old', 'refresh_token' => 'refresh', 'expires_at' => 1.minute.ago.to_i }
      end
    end
  end
end
