require 'test_helper'

module AnyAuth
  module Strategies
    class AppleTest < ActiveSupport::TestCase
      KEY = OpenSSL::PKey::EC.generate('prime256v1')

      test 'leaving asks for the email and the name, to be posted back' do
        sent = query_of(apple.request_phase(redirect_uri: 'https://tavle.test/callback').url)

        assert_equal 'openid email name', sent['scope']
        assert_equal 'form_post', sent['response_mode']
      end

      test 'the client secret is signed with our key, names the team and the client, and is short-lived' do
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
      end

      test 'Apple vouches as text or as a boolean, and an address it does not vouch for is not confirmed' do
        assert_predicate auth(email: 'mette@icloud.com', email_verified: true).info, :email_verified
        assert_not auth(email: 'mette@icloud.com', email_verified: 'false').info.email_verified
        assert_not auth(email: 'mette@icloud.com').info.email_verified
      end

      test 'the name is what Apple posts the first time' do
        posted = { name: { firstName: 'Mette', lastName: 'Holm' } }.to_json

        assert_equal 'Mette Holm', auth(user: posted).info.name
      end

      test 'there is no name when Apple posts none, or posts something else' do
        assert_nil auth.info.name
        assert_nil auth(user: 'not json').info.name
        assert_nil auth(user: '{"name":"Mette"}').info.name
      end

      test 'a token from another issuer is refused' do
        assert_raises(Unauthorized) { auth(iss: 'https://evil.test') }
      end

      private

      def apple
        Apple.new(client_id: 'com.tavle.web', team_id: 'TEAM123456', key_id: 'KEY1234567', private_key: KEY.to_pem)
      end

      def auth(user: nil, **claims)
        claims = { sub: 'a-1', iss: 'https://appleid.apple.com', aud: 'com.tavle.web', exp: 1.hour.from_now.to_i,
                   nonce: 'n' }.merge(claims)
        stub_json(:post, 'https://appleid.apple.com/auth/token', access_token: 'adgang', id_token: id_token(claims))

        apple.callback_phase({ 'code' => 'kode', 'state' => 's', 'user' => user }.compact,
          { 'state' => 's', 'nonce' => 'n', 'redirect_uri' => 'https://tavle.test/callback' })
      end
    end
  end
end
