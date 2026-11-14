# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class GoogleTest < ActiveSupport::TestCase
      TOKEN_URL = 'https://oauth2.googleapis.com/token'

      test 'Google names the person, with their picture, and hands over what it said' do
        google = auth(name: 'Mette Holm', picture: 'https://g.test/m.png', hd: 'acme.test')

        assert_equal 'g-1', google.uid
        assert_equal 'Mette Holm', google.info.name
        assert_equal 'https://g.test/m.png', google.info.image
        assert_equal 'acme.test', google.raw['hd']
      end

      test 'Google speaks for a verified Gmail address' do
        assert_predicate info(email: 'Mette@Gmail.com', email_verified: true), :email_verified
      end

      test 'Google speaks for a Workspace address only when it names the domain' do
        named = info(email: 'mette@acme.test', email_verified: true, hd: 'acme.test')
        unnamed = info(email: 'mette@acme.test', email_verified: true)

        assert_predicate named, :email_verified
        assert_not unnamed.email_verified
      end

      test 'an address Google has not verified is never confirmed' do
        assert_not info(email: 'mette@gmail.com', email_verified: false).email_verified
      end

      test 'a token from another issuer, or naming nobody, is refused' do
        assert_raises(Unauthorized) { auth(iss: 'https://evil.test') }
        assert_raises(Unauthorized) { auth(sub: nil) }
      end

      private

      def info(**claims)
        auth(**claims).info
      end

      def auth(**claims)
        claims = {
          sub: 'g-1',
          iss: 'https://accounts.google.com',
          aud: 'app',
          exp: 1.hour.from_now.to_i,
          nonce: 'n',
        }.merge(claims)
        stub_json(:post, TOKEN_URL, access_token: 'adgang', id_token: id_token(claims))
        google = Google.new(client_id: 'app', client_secret: 'tys')

        google.callback_phase(callback_params, stored_session(nonce: 'n'))
      end
    end
  end
end
