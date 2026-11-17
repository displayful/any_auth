# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class HubspotTest < ActiveSupport::TestCase
      TOKEN_URL = 'https://api.hubspot.com/oauth/2026-09/token'
      INTROSPECT_URL = 'https://api.hubspot.com/oauth/2026-09/token/introspect'

      setup do
        stub_json(:post, TOKEN_URL, access_token: 'new')
      end

      test 'HubSpot names the user who signed in, and says which portal they opened' do
        stub_json(:post, INTROSPECT_URL, active: true, user_id: 41, user: 'mette@acme.test',
          hub_id: 8823, token: 'new')

        auth = come_home

        assert_equal '41', auth.uid
        assert_equal 'mette@acme.test', auth.info.email
        assert_not auth.info.email_verified
        assert_equal 8823, auth.raw['hub_id']
        assert_nil auth.raw['token']
      end

      test 'the scopes HubSpot sends as a list are credentials scope' do
        stub_json(:post, TOKEN_URL, access_token: 'new', scopes: %w[oauth crm.objects.deals.read])
        stub_json(:post, INTROSPECT_URL, active: true, user_id: 41)

        assert_equal 'oauth crm.objects.deals.read', come_home.credentials['scope']
      end

      test 'leaving sends a PKCE challenge, and the swap sends its verifier' do
        hubspot = Hubspot.new(client_id: 'app', client_secret: 'secret')
        request = hubspot.request_phase(redirect_uri: CALLBACK_URL)
        verifier = request.session['code_verifier']
        stub_json(:post, INTROSPECT_URL, active: true, user_id: 41)

        hubspot.callback_phase(callback_params, stored_session(code_verifier: verifier))

        assert_equal challenge_for(verifier), query_of(request.url)['code_challenge']
        assert_requested :post, TOKEN_URL, body: hash_including(code_verifier: verifier)
      end

      test 'the token is asked about in the body, never in the address' do
        asked = stub_json(:post, INTROSPECT_URL, active: true, user_id: 41)
          .with(body: { client_id: 'app', client_secret: 'secret',
                        token_type_hint: 'access_token', token: 'new' })

        come_home

        assert_requested asked
      end

      test 'a token HubSpot no longer counts as active is AccessDenied' do
        stub_json(:post, INTROSPECT_URL, active: false, user_id: 41)

        assert_raises(AccessDenied) { come_home }
      end

      test 'an answer that cannot be read is Unavailable' do
        stub_request(:post, INTROSPECT_URL).to_return(
          headers: { 'Content-Type' => 'text/html' },
          body: '<html>'
        )

        assert_raises(Unavailable) { come_home }
      end

      private

      def come_home
        hubspot = Hubspot.new(client_id: 'app', client_secret: 'secret')

        hubspot.callback_phase(callback_params, stored_session)
      end
    end
  end
end
