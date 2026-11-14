require 'test_helper'

module AnyAuth
  module Strategies
    class OpenIDConnectTest < ActiveSupport::TestCase
      TOKEN_URL = 'https://oauth2.googleapis.com/token'.freeze
      CALLBACK = 'https://tavle.test/callback'.freeze

      test 'leaving asks who the person is, with a nonce and a challenge only this sign-in can answer' do
        request = google.request_phase(redirect_uri: CALLBACK)
        sent = query_of(request.url)

        assert_equal 'openid email profile', sent['scope']
        assert_equal request.session['nonce'], sent['nonce']
        assert_equal Base64.urlsafe_encode64(Digest::SHA256.digest(request.session['code_verifier']), padding: false),
          sent['code_challenge']
      end

      test 'asked for something else, it still asks who the person is' do
        request = google.request_phase(redirect_uri: CALLBACK, scope: 'https://www.googleapis.com/auth/drive.file')

        assert_equal 'openid https://www.googleapis.com/auth/drive.file', query_of(request.url)['scope']
      end

      test 'what the caller asks for cannot replace the state or the nonce' do
        request = google.request_phase(redirect_uri: CALLBACK, state: 'mine', nonce: 'mine')
        sent = query_of(request.url)

        assert_equal request.session['state'], sent['state']
        assert_equal request.session['nonce'], sent['nonce']
      end

      test 'the code is swapped together with the verifier, and the ID token says who signed in' do
        auth = come_home_with(sub: 'g-1')

        assert_equal 'g-1', auth.uid
        assert_equal 'app', auth.raw['aud']
        assert_requested :post, TOKEN_URL, body: hash_including('code' => 'kode', 'code_verifier' => 'v')
      end

      test 'a token for another sign-in, or that has expired, is refused' do
        assert_raises(Unauthorized) { come_home_with(nonce: 'another') }
        assert_raises(Unauthorized) { come_home_with(nonce: nil) }
        assert_raises(Unauthorized) { come_home_with(exp: 1.minute.ago.to_i) }
      end

      test 'a token for another client, or for several without saying it is ours, is refused' do
        assert_raises(Unauthorized) { come_home_with(aud: 'another-app') }
        assert_raises(Unauthorized) { come_home_with(aud: %w[app another-app]) }
        assert_raises(Unauthorized) { come_home_with(aud: 'app', azp: 'another-app') }
        assert_equal 'g-1', come_home_with(aud: %w[app another-app], azp: 'app').uid
      end

      test 'an answer with no ID token, or one that cannot be read, names nobody' do
        stub_json(:post, TOKEN_URL, access_token: 'adgang')

        assert_raises(Unauthorized) { come_home }

        stub_json(:post, TOKEN_URL, access_token: 'adgang', id_token: 'not-a-token')

        assert_raises(Unauthorized) { come_home }
      end

      private

      def google
        Google.new(client_id: 'app', client_secret: 'tys')
      end

      def come_home_with(**claims)
        claims = { sub: 'g-1', iss: 'https://accounts.google.com', aud: 'app', exp: 1.hour.from_now.to_i,
                   nonce: 'n' }.merge(claims)
        stub_json(:post, TOKEN_URL, access_token: 'adgang', id_token: id_token(claims))

        come_home
      end

      def come_home
        google.callback_phase({ 'code' => 'kode', 'state' => 's' },
          { 'state' => 's', 'nonce' => 'n', 'code_verifier' => 'v', 'redirect_uri' => CALLBACK })
      end
    end
  end
end
