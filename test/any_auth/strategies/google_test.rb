require 'test_helper'

module AnyAuth
  module Strategies
    class GoogleTest < ActiveSupport::TestCase
      test 'Google speaks for a verified Gmail address' do
        assert_predicate info(email: 'Mette@Gmail.com', email_verified: true), :email_verified
      end

      test 'Google speaks for a Workspace address only when it names the domain' do
        assert_predicate info(email: 'mette@acme.test', email_verified: true, hd: 'acme.test'), :email_verified
        assert_not info(email: 'mette@acme.test', email_verified: true).email_verified
      end

      test 'an unverified address is never confirmed' do
        assert_not info(email: 'mette@gmail.com', email_verified: false).email_verified
      end

      test 'a token from another issuer, for another sign-in, or that has expired, is refused' do
        assert_raises(Unauthorized) { auth(iss: 'https://evil.test') }
        assert_raises(Unauthorized) { auth(nonce: 'another') }
        assert_raises(Unauthorized) { auth(exp: 1.minute.ago.to_i) }
      end

      test 'a token naming no subject is refused' do
        assert_raises(Unauthorized) { auth(sub: nil) }
      end

      test 'leaving asks who the person is, and remembers the nonce and the verifier' do
        request = Google.new(client_id: 'app').request_phase(redirect_uri: 'https://tavle.test/callback')
        sent = Rack::Utils.parse_query(URI(request.url).query)

        assert_equal 'openid email profile', sent['scope']
        assert_equal request.session['state'], sent['state']
        assert_equal request.session['nonce'], sent['nonce']
        assert_equal Base64.urlsafe_encode64(Digest::SHA256.digest(request.session['code_verifier']), padding: false),
          sent['code_challenge']
      end

      test 'asked for something else, it still asks who the person is' do
        request = Google.new(client_id: 'app').request_phase(redirect_uri: 'https://tavle.test/callback',
          scope: 'https://www.googleapis.com/auth/drive.file')

        assert_equal 'openid https://www.googleapis.com/auth/drive.file',
          Rack::Utils.parse_query(URI(request.url).query)['scope']
      end

      test 'an ID token is not for us when no nonce was sent' do
        unbound = { sub: 'g-1', iss: 'https://accounts.google.com', aud: 'app', exp: 1.hour.from_now.to_i }
        stub_request(:post, 'https://oauth2.googleapis.com/token')
          .to_return(headers: { 'Content-Type' => 'application/json' },
            body: { access_token: 'adgang', id_token: JWT.encode(unbound, nil, 'none') }.to_json)

        assert_raises(Unauthorized) do
          Google.new(client_id: 'app', client_secret: 'tys').callback_phase({ 'code' => 'kode', 'state' => 's' },
            { 'state' => 's', 'redirect_uri' => 'https://tavle.test/callback' })
        end
      end

      test 'an answer with no ID token names nobody, and is refused' do
        stub_request(:post, 'https://oauth2.googleapis.com/token')
          .to_return(headers: { 'Content-Type' => 'application/json' }, body: { access_token: 'adgang' }.to_json)

        assert_raises(Unauthorized) do
          Google.new(client_id: 'app', client_secret: 'tys').callback_phase({ 'code' => 'kode', 'state' => 's' },
            { 'state' => 's', 'nonce' => 'n', 'redirect_uri' => 'https://tavle.test/callback' })
        end
      end

      private

      def info(**claims)
        auth(**claims).info
      end

      def auth(**overrides)
        payload = {
          sub: 'g-1',
          iss: 'https://accounts.google.com',
          aud: %w[app],
          exp: 1.hour.from_now.to_i,
          nonce: 'n',
        }.merge(overrides)
        stub_request(:post, 'https://oauth2.googleapis.com/token')
          .with(body: hash_including('code_verifier' => 'v'))
          .to_return(headers: { 'Content-Type' => 'application/json' },
            body: { access_token: 'adgang', id_token: JWT.encode(payload, nil, 'none') }.to_json)

        Google.new(client_id: 'app', client_secret: 'tys').callback_phase({ 'code' => 'kode', 'state' => 's' },
          { 'state' => 's', 'nonce' => 'n', 'code_verifier' => 'v', 'redirect_uri' => 'https://tavle.test/callback' })
      end
    end
  end
end
