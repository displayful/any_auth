require 'test_helper'

module AnyAuth
  module Strategies
    class AppleTest < ActiveSupport::TestCase
      KEY = OpenSSL::PKey::EC.generate('prime256v1')

      test 'leaving asks for the email and the name, to be posted back' do
        sent = Rack::Utils.parse_query(URI(apple.request_phase(redirect_uri: 'https://tavle.test/callback').url).query)

        assert_equal 'openid email name', sent['scope']
        assert_equal 'form_post', sent['response_mode']
        assert_equal 'com.tavle.web', sent['client_id']
      end

      test 'the secret is signed with our key, names the team and the client, and is short-lived' do
        claims, header = JWT.decode(apple.client_secret, KEY, true, algorithm: 'ES256')

        assert_equal 'KEY1234567', header['kid']
        assert_equal %w[TEAM123456 com.tavle.web https://appleid.apple.com], claims.values_at('iss', 'sub', 'aud')
        assert_operator claims['exp'], :<=, 5.minutes.from_now.to_i
      end

      test 'Apple names the person by their subject, with the email it vouches for' do
        apple = auth(email: 'mette@icloud.com', email_verified: 'true')

        assert_equal 'a-1', apple.uid
        assert_equal 'mette@icloud.com', apple.info.email
        assert_predicate apple.info, :email_verified
        assert_equal 'https://appleid.apple.com', apple.raw['iss']
      end

      test 'an address Apple does not vouch for is not confirmed' do
        assert_not auth(email: 'mette@icloud.com', email_verified: 'false').info.email_verified
        assert_not auth(email: 'mette@icloud.com').info.email_verified
        assert_predicate auth(email: 'mette@icloud.com', email_verified: true).info, :email_verified
      end

      test 'the name comes from what Apple posts the first time, and is nobody otherwise' do
        user = { name: { firstName: 'Mette', lastName: 'Holm' } }.to_json

        assert_equal 'Mette Holm', auth(user:).info.name
        assert_nil auth.info.name
        assert_nil auth(user: 'not json').info.name
        assert_nil auth(user: '[1]').info.name
        assert_nil auth(user: '{"name":"Mette"}').info.name
      end

      test 'a token from another issuer, for another sign-in or another client, is refused' do
        assert_raises(Unauthorized) { auth(iss: 'https://evil.test') }
        assert_raises(Unauthorized) { auth(nonce: 'another') }
        assert_raises(Unauthorized) { auth(aud: 'another-app') }
        assert_raises(Unauthorized) { auth(exp: 1.minute.ago.to_i) }
      end

      private

      def apple
        Apple.new(client_id: 'com.tavle.web', team_id: 'TEAM123456', key_id: 'KEY1234567', private_key: KEY.to_pem)
      end

      def auth(user: nil, **overrides)
        payload = {
          sub: 'a-1',
          iss: 'https://appleid.apple.com',
          aud: 'com.tavle.web',
          exp: 1.hour.from_now.to_i,
          nonce: 'n',
        }.merge(overrides)
        stub_request(:post, 'https://appleid.apple.com/auth/token')
          .with(body: hash_including('client_id' => 'com.tavle.web', 'code' => 'kode'))
          .to_return(headers: { 'Content-Type' => 'application/json' },
            body: { access_token: 'adgang', id_token: JWT.encode(payload, nil, 'none') }.to_json)

        apple.callback_phase({ 'code' => 'kode', 'state' => 's', 'user' => user }.compact,
          { 'state' => 's', 'nonce' => 'n', 'code_verifier' => 'v', 'redirect_uri' => 'https://tavle.test/callback' })
      end
    end
  end
end
