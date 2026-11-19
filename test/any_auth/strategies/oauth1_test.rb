# frozen_string_literal: true

require 'test_helper'
require 'any_auth/strategies/oauth1'

module AnyAuth
  module Strategies
    class OAuth1Test < ActiveSupport::TestCase
      class Vendor < OAuth1
        def client_options
          {
            site: 'https://api.vendor.test',
            request_token_path: '/oauth/request_token',
            authorize_path: '/oauth/authorize',
            access_token_path: '/oauth/access_token',
          }
        end

        private

        def identity(access_token, _session)
          user = get(access_token, '/1/me')

          { uid: user['id'].to_s, info: Info.new(name: user['name']), raw: user }
        end
      end

      REQUEST_TOKEN_URL = 'https://api.vendor.test/oauth/request_token'
      ACCESS_TOKEN_URL = 'https://api.vendor.test/oauth/access_token'
      KEPT = { 'request_token' => 'request', 'request_token_secret' => 'request-secret' }.freeze

      test 'leaving asks for a request token with our callback, and sends the person on' do
        stub_form(:post, REQUEST_TOKEN_URL, oauth_token: 'request',
          oauth_token_secret: 'request-secret', oauth_callback_confirmed: true)

        request = vendor.request_phase(redirect_uri: CALLBACK_URL)

        assert_equal 'https://api.vendor.test/oauth/authorize?oauth_token=request', request.url
        assert_equal KEPT, request.session
        assert_requested :post, REQUEST_TOKEN_URL,
          headers: { 'Authorization' => /oauth_callback="#{CGI.escape(CALLBACK_URL)}"/ }
      end

      test 'a vendor that does not confirm our callback speaks OAuth 1.0, which is refused' do
        stub_form(:post, REQUEST_TOKEN_URL, oauth_token: 'request',
          oauth_token_secret: 'request-secret')

        assert_raises(ConfigurationError) { vendor.request_phase(redirect_uri: CALLBACK_URL) }
      end

      test 'coming back swaps the verifier for a token and its secret, then asks who it is' do
        stub_form(:post, ACCESS_TOKEN_URL, oauth_token: 'access',
          oauth_token_secret: 'access-secret')
        stub_json(:get, 'https://api.vendor.test/1/me', id: 7, name: 'Mette Holm')

        auth = vendor.callback_phase(answer, KEPT)

        assert_equal({ 'token' => 'access', 'secret' => 'access-secret' }, auth.credentials)
        assert_equal '7', auth.uid
        assert_equal 'Mette Holm', auth.info.name
        assert_requested :post, ACCESS_TOKEN_URL,
          headers: { 'Authorization' => /oauth_verifier="verifier"/ }
      end

      test 'a callback for another request token, or with nothing kept, did not start here' do
        forged = answer(oauth_token: 'forged')

        assert_raises(InvalidCallback) { vendor.callback_phase(forged, KEPT) }
        assert_raises(InvalidCallback) { vendor.callback_phase(answer, {}) }
      end

      test 'a callback with no verifier is not a sign-in' do
        without_verifier = { 'oauth_token' => 'request' }

        assert_raises(InvalidCallback) { vendor.callback_phase(without_verifier, KEPT) }
      end

      test 'a person who declined is AccessDenied' do
        assert_raises(AccessDenied) { vendor.callback_phase({ 'denied' => 'request' }, KEPT) }
      end

      test 'a swap the vendor refuses is AccessDenied, and a vendor that is down is Unavailable' do
        stub_request(:post, ACCESS_TOKEN_URL).to_return(status: 401)

        assert_raises(AccessDenied) { vendor.callback_phase(answer, KEPT) }

        stub_request(:post, ACCESS_TOKEN_URL).to_return(status: 503)

        assert_raises(Unavailable) { vendor.callback_phase(answer, KEPT) }

        stub_request(:post, ACCESS_TOKEN_URL).to_timeout

        assert_raises(Unavailable) { vendor.callback_phase(answer, KEPT) }
      end

      test "a refusal carries OAuth 1's problem and advice" do
        stub_request(:post, ACCESS_TOKEN_URL).to_return(
          status: 401,
          body: 'oauth_problem=token_expired&oauth_problem_advice=Sign+in+again'
        )

        refused = assert_raises(AccessDenied) { vendor.callback_phase(answer, KEPT) }

        assert_equal 'token_expired', refused.code
        assert_equal 'Sign in again', refused.description
      end

      test 'a vendor that does not know our key is a ConfigurationError' do
        stub_request(:post, ACCESS_TOKEN_URL).to_return(
          status: 401,
          body: 'oauth_problem=consumer_key_unknown'
        )

        assert_raises(ConfigurationError) { vendor.callback_phase(answer, KEPT) }
      end

      test 'credentials do not expire, so a refresh answers them as they are' do
        credentials = { 'token' => 'access', 'secret' => 'access-secret' }

        assert_equal credentials, vendor.refresh(credentials)
      end

      test 'a vendor gets 5 seconds to connect and 10 to answer' do
        http = vendor.send(:consumer).http

        assert_equal 5, http.open_timeout
        assert_equal 10, http.read_timeout
      end

      private

      def vendor
        Vendor.new(consumer_key: 'app', consumer_secret: 'secret')
      end

      def answer(**more)
        { 'oauth_token' => 'request', 'oauth_verifier' => 'verifier' }.merge(more.stringify_keys)
      end

      def stub_form(method, url, **body)
        stub_request(method, url).to_return(
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
          body: body.to_query
        )
      end
    end
  end
end
