require 'test_helper'

module AnyAuth
  module Strategies
    class CredentialsTest < ActiveSupport::TestCase
      test 'each vendor is shown its credentials its own way' do
        assert_equal({ 'Authorization' => 'Bearer adgang' }, Hubspot.new.authorization('access_token' => 'adgang'))
        assert_equal({ 'X-Shopify-Access-Token' => 'adgang' }, Shopify.new.authorization('access_token' => 'adgang'))
        assert_equal({ 'Authorization' => 'Basic YXBpOmhlbW1lbGlndA==' },
          Adversus.new.authorization('username' => 'api', 'password' => 'hemmeligt'))
        assert_equal({ 'X-AppSecretToken' => 'app', 'X-AgreementGrantToken' => 'aftale' },
          Economic.new.authorization('app_token' => 'app', 'agreement_token' => 'aftale'))
      end

      test 'credentials still good, or that never expire, are answered as they are' do
        good = { 'access_token' => 'adgang', 'expires_at' => 1.hour.from_now.utc.iso8601 }
        pasted = { 'username' => 'api', 'password' => 'hemmeligt' }

        assert_equal good, hubspot.fresh(good)
        assert_equal({ 'access_token' => 'adgang' }, hubspot.fresh({ 'access_token' => 'adgang' }))
        assert_equal pasted, Adversus.new.fresh(pasted)
        assert_not_requested :post, 'https://api.hubapi.com/oauth/v1/token'
      end

      test 'credentials about to expire are renewed, keeping a refresh token the vendor did not replace' do
        stub_request(:post, 'https://api.hubapi.com/oauth/v1/token')
          .to_return(headers: { 'Content-Type' => 'application/json' },
            body: { access_token: 'nyere', expires_in: 1800 }.to_json)

        fresh = hubspot.fresh('access_token' => 'gammel', 'refresh_token' => 'igen',
          'expires_at' => 1.minute.from_now.utc.iso8601)

        assert_equal 'nyere', fresh['access_token']
        assert_equal 'igen', fresh['refresh_token']
      end

      test 'a developer comes straight home as whoever they say they are' do
        request = Developer.new(email: ' Mette@Acme.test ').request_phase(redirect_uri: 'https://tavle.test/home')
        home = URI(request.url)
        params = Rack::Utils.parse_query(home.query)

        auth = Developer.new.callback_phase(params, request.session)

        assert_equal 'tavle.test', home.host
        assert_equal 'developer', auth.provider
        assert_equal 'mette@acme.test', auth.uid
        assert_predicate auth.info, :email_verified
      end

      test 'a developer callback nobody started here, or naming nobody, is not a sign-in' do
        request = Developer.new.request_phase(redirect_uri: 'https://tavle.test/home')
        params = Rack::Utils.parse_query(URI(request.url).query)

        assert_raises(InvalidCallback) { Developer.new.callback_phase(params, request.session) }
        assert_raises(InvalidCallback) { Developer.new.callback_phase(params.merge('email' => 'a@b.test'), nil) }
        assert_raises(InvalidCallback) do
          Developer.new.callback_phase({ 'email' => 'a@b.test', 'state' => 'forged' }, request.session)
        end
      end

      private

      def hubspot
        Hubspot.new(client_id: 'app', client_secret: 'tys')
      end
    end
  end
end
