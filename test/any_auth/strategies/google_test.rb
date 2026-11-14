require 'test_helper'

module AnyAuth
  module Strategies
    class GoogleTest < ActiveSupport::TestCase
      test 'Google names the person, with their picture, and hands over what it said' do
        google = auth(email: 'mette@gmail.com', name: 'Mette Holm', picture: 'https://g.test/m.png', hd: 'acme.test')

        assert_equal 'g-1', google.uid
        assert_equal 'Mette Holm', google.info.name
        assert_equal 'https://g.test/m.png', google.info.image
        assert_equal 'acme.test', google.raw['hd']
      end

      test 'Google speaks for a verified Gmail address' do
        assert_predicate auth(email: 'Mette@Gmail.com', email_verified: true).info, :email_verified
      end

      test 'Google speaks for a Workspace address only when it names the domain' do
        assert_predicate auth(email: 'mette@acme.test', email_verified: true, hd: 'acme.test').info, :email_verified
        assert_not auth(email: 'mette@acme.test', email_verified: true).info.email_verified
      end

      test 'an address Google has not verified is never confirmed' do
        assert_not auth(email: 'mette@gmail.com', email_verified: false).info.email_verified
      end

      test 'a token from another issuer, or naming nobody, is refused' do
        assert_raises(Unauthorized) { auth(iss: 'https://evil.test') }
        assert_raises(Unauthorized) { auth(sub: nil) }
      end

      private

      def auth(**claims)
        claims = { sub: 'g-1', iss: 'https://accounts.google.com', aud: 'app', exp: 1.hour.from_now.to_i,
                   nonce: 'n' }.merge(claims)
        stub_json(:post, 'https://oauth2.googleapis.com/token', access_token: 'adgang', id_token: id_token(claims))

        Google.new(client_id: 'app', client_secret: 'tys').callback_phase({ 'code' => 'kode', 'state' => 's' },
          { 'state' => 's', 'nonce' => 'n', 'redirect_uri' => 'https://tavle.test/callback' })
      end
    end
  end
end
