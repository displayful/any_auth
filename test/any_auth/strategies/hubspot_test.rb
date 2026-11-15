# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class HubspotTest < ActiveSupport::TestCase
      TOKEN_INFO_URL = 'https://api.hubapi.com/oauth/v1/access-tokens/new'

      setup do
        stub_json(:post, 'https://api.hubapi.com/oauth/v1/token', access_token: 'new')
      end

      test 'HubSpot names the user who signed in, and says which portal they opened' do
        stub_json(:get, TOKEN_INFO_URL, user_id: 41, user: 'mette@acme.test', hub_id: 8823,
          token: 'new')

        auth = come_home

        assert_equal '41', auth.uid
        assert_equal 'mette@acme.test', auth.info.email
        assert_not auth.info.email_verified
        assert_equal 8823, auth.raw['hub_id']
        assert_nil auth.raw['token']
      end

      test "a refresh HubSpot refuses carries HubSpot's own code and message" do
        refusal = { status: 'BAD_REFRESH_TOKEN', message: 'missing or invalid refresh token' }
        stub_request(:post, 'https://api.hubapi.com/oauth/v1/token').to_return(
          status: 400,
          headers: { 'Content-Type' => 'application/json' },
          body: refusal.to_json
        )
        hubspot = Hubspot.new(client_id: 'app', client_secret: 'secret')

        refused = assert_raises(AccessDenied) { hubspot.refresh!('refresh_token' => 'old') }

        assert_equal 'BAD_REFRESH_TOKEN', refused.code
        assert_equal 'missing or invalid refresh token', refused.description
      end

      test 'a token HubSpot names no user for is AccessDenied' do
        stub_json(:get, TOKEN_INFO_URL, message: 'unknown token')

        assert_raises(AccessDenied) { come_home }
      end

      test 'an answer that cannot be read is Unavailable' do
        stub_request(:get, TOKEN_INFO_URL).to_return(
          headers: { 'Content-Type' => 'text/html' },
          body: '<html>'
        )

        assert_raises(Unavailable) { come_home }
      end

      test 'a refusal never repeats the token that was in the address' do
        stub_request(:get, TOKEN_INFO_URL).to_return(status: 401)

        refused = assert_raises(AccessDenied) { come_home }

        assert_nil refused.cause
        assert_not_includes refused.message, 'new'
      end

      private

      def come_home
        hubspot = Hubspot.new(client_id: 'app', client_secret: 'secret')

        hubspot.callback_phase(callback_params, stored_session)
      end
    end
  end
end
