require 'test_helper'
require 'any_auth/strategies/developer'

module AnyAuth
  module Strategies
    class CredentialsTest < ActiveSupport::TestCase
      test 'credentials still good, or that never expire, are answered as they are' do
        good = { 'access_token' => 'adgang', 'expires_at' => 1.hour.from_now.utc.iso8601 }
        pasted = { 'username' => 'api', 'password' => 'hemmeligt' }

        assert_equal good, hubspot.refresh(good)
        assert_equal({ 'access_token' => 'adgang' }, hubspot.refresh({ 'access_token' => 'adgang' }))
        assert_equal pasted, Adversus.new.refresh(pasted)
        assert_not_requested :post, 'https://api.hubapi.com/oauth/v1/token'
      end

      test 'expiry is read whether it was stored as text, as a number or under symbol keys' do
        assert hubspot.expired?('expires_at' => 1.minute.from_now.to_i)
        assert hubspot.expired?(expires_at: 1.minute.from_now.utc.iso8601)
        assert hubspot.expired?('expires_at' => 'not a time')
        assert_not hubspot.expired?('expires_at' => 3.minutes.from_now.to_i)
      end

      test 'a renewal that names no new expiry forgets the old one' do
        stub_request(:post, 'https://api.hubapi.com/oauth/v1/token')
          .to_return(headers: { 'Content-Type' => 'application/json' }, body: { access_token: 'nyere' }.to_json)

        renewed = hubspot.refresh('access_token' => 'gammel', 'refresh_token' => 'igen',
          'expires_at' => 1.minute.ago.utc.iso8601)

        assert_not hubspot.expired?(renewed)
      end

      test 'credentials about to expire are renewed, keeping a refresh token the vendor did not replace' do
        stub_request(:post, 'https://api.hubapi.com/oauth/v1/token')
          .to_return(headers: { 'Content-Type' => 'application/json' },
            body: { access_token: 'nyere', expires_in: 1800 }.to_json)

        renewed = hubspot.refresh('access_token' => 'gammel', 'refresh_token' => 'igen',
          'expires_at' => 1.minute.from_now.utc.iso8601)

        assert_equal 'nyere', renewed['access_token']
        assert_equal 'igen', renewed['refresh_token']
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

      test 'a developer has to say who they are before leaving' do
        assert_predicate Developer.new(email: 'mette@acme.test'), :valid?
        assert_includes Developer.new.tap(&:valid?).errors.attribute_names, :email
      end

      test 'a developer callback nobody started here, or naming nobody, is not a sign-in' do
        request = Developer.new.request_phase(redirect_uri: 'https://tavle.test/home')
        params = Rack::Utils.parse_query(URI(request.url).query)

        assert_raises(InvalidCallback) { Developer.new.callback_phase(params, request.session) }
        assert_raises(InvalidCallback) { Developer.new.callback_phase(params.merge('email' => 'a@b.test'), nil) }
        assert_raises(InvalidCallback) do
          Developer.new.callback_phase({ 'email' => 'a@b.test', 'state' => 'forged' }, request.session)
        end
        assert_raises(InvalidCallback) do
          Developer.new.callback_phase(params.merge('email' => ['a@b.test']), request.session)
        end
      end

      test 'a developer keeps what the address to come home to already asked' do
        request = Developer.new(email: 'a@b.test').request_phase(redirect_uri: 'https://tavle.test/home?tenant=7')

        assert_equal '7', Rack::Utils.parse_query(URI(request.url).query)['tenant']
      end

      private

      def hubspot
        Hubspot.new(client_id: 'app', client_secret: 'tys')
      end
    end
  end
end
