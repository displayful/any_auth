# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class TavleTest < ActiveSupport::TestCase
      USERINFO_URL = 'https://tavle.co/oauth/userinfo'

      setup do
        stub_json(:post, 'https://tavle.co/oauth/token', access_token: 'new')
      end

      test 'leaving sends a PKCE challenge, which Tavle requires' do
        request = tavle.request_phase(redirect_uri: CALLBACK_URL)
        sent = query_of(request.url)

        assert request.url.start_with?('https://tavle.co/oauth/authorize?')
        assert_equal challenge_for(request.session['code_verifier']), sent['code_challenge']
      end

      test 'Tavle names the member who signed in, and says which company they are in' do
        stub_json(:get, USERINFO_URL, sub: '34', name: 'Mette Holm', email: 'mette@acme.test',
          email_verified: true, company: { id: 7, name: 'Acme' }, givenName: 'Mette')

        auth = tavle.callback_phase(callback_params, stored_session)

        assert_equal '34', auth.uid
        assert_equal 'Mette Holm', auth.info.name
        assert_equal 'mette@acme.test', auth.info.email
        assert_predicate auth.info, :email_verified
        assert_equal 7, auth.raw.dig('company', 'id')
        assert_equal 'Mette', auth.raw['givenName']
        assert_instance_of Hash, auth.raw
        assert_requested :get, USERINFO_URL, headers: { 'Authorization' => 'Bearer new' }
      end

      test 'a token Tavle names nobody for is AccessDenied' do
        stub_json(:get, USERINFO_URL, error: 'invalid_token')

        assert_raises(AccessDenied) { tavle.callback_phase(callback_params, stored_session) }
      end

      private

      def tavle
        Tavle.new(client_id: 'app', client_secret: 'secret')
      end
    end
  end
end
