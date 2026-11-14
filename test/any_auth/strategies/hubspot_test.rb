require 'test_helper'

module AnyAuth
  module Strategies
    class HubspotTest < ActiveSupport::TestCase
      TOKEN_INFO_URL = 'https://api.hubapi.com/oauth/v1/access-tokens/ny'.freeze

      setup do
        stub_json(:post, 'https://api.hubapi.com/oauth/v1/token', access_token: 'ny')
      end

      test 'HubSpot names the user who signed in, and says which portal they opened' do
        stub_json(:get, TOKEN_INFO_URL, user_id: 41, user: 'mette@acme.test', hub_id: 8823, token: 'ny')

        auth = come_home

        assert_equal '41', auth.uid
        assert_equal 'mette@acme.test', auth.info.email
        assert_not auth.info.email_verified
        assert_equal 8823, auth.raw['hub_id']
        assert_nil auth.raw['token']
      end

      test 'a token HubSpot names no user for is Unauthorized' do
        stub_json(:get, TOKEN_INFO_URL, message: 'unknown token')

        assert_raises(Unauthorized) { come_home }
      end

      test 'an answer that cannot be read is Unavailable' do
        stub_request(:get, TOKEN_INFO_URL).to_return(headers: { 'Content-Type' => 'text/html' }, body: '<html>')

        assert_raises(Unavailable) { come_home }
      end

      test 'a refusal never repeats the token that was in the address' do
        stub_request(:get, TOKEN_INFO_URL).to_return(status: 401)

        refused = assert_raises(Unauthorized) { come_home }

        assert_nil refused.cause
        assert_not_includes refused.message, 'ny'
      end

      private

      def come_home
        Hubspot.new(client_id: 'app', client_secret: 'tys').callback_phase({ 'code' => 'kode', 'state' => 's' },
          { 'state' => 's', 'redirect_uri' => 'https://tavle.test/callback' })
      end
    end
  end
end
