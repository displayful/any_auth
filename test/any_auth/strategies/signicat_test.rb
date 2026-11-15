# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class SignicatTest < ActiveSupport::TestCase
      DOMAIN = 'acme.app.signicat.com'
      ISSUER = 'https://acme.app.signicat.com/auth/open'
      TOKEN_URL = 'https://acme.app.signicat.com/auth/open/connect/token'

      test 'signing in happens at your own Signicat domain, with the eID and level asked for' do
        request = signicat.request_phase(redirect_uri: CALLBACK_URL)
        query = query_of(request.url)

        assert request.url.start_with?('https://acme.app.signicat.com/auth/open/connect/authorize')
        assert_equal 'idp:mitid loa:substantial', query['acr_values']
        assert_equal 'openid profile', query['scope']
        assert_equal 'S256', query['code_challenge_method']
        assert_equal request.session['nonce'], query['nonce']
      end

      test 'several eIDs are offered as one choice' do
        request = signicat(idp: %w[nbid sbid], loa: nil).request_phase(redirect_uri: CALLBACK_URL)

        assert_equal 'idp:nbid,sbid', query_of(request.url)['acr_values']
      end

      test 'a person is who Signicat says, and the eID they used comes along' do
        auth = auth(sub: 'hashed-subject', name: 'Mette Hansen', idp: 'mitid', acr: 'substantial')

        assert_equal 'hashed-subject', auth.uid
        assert_equal 'Mette Hansen', auth.info.name
        assert_equal 'mitid', auth.raw['idp']
      end

      test 'a token from another Signicat domain is refused' do
        assert_raises(InvalidCallback) { auth(iss: 'https://other.app.signicat.com/auth/open') }
      end

      test 'a token from another eID than the one asked for is refused' do
        assert_raises(InvalidCallback) { auth(idp: 'otp-sms') }
      end

      test 'a token below the level asked for is refused, and one above it accepted' do
        assert_raises(InvalidCallback) { auth(acr: 'low') }
        assert_raises(InvalidCallback) { auth(acr: nil) }

        assert_equal 'high', auth(acr: 'high').raw['acr']
      end

      test 'a person who cancels at Signicat is AccessDenied' do
        cancelled = callback_params(code: nil, error: 'access_denied',
          error_description: 'AGW-3200 The authentication was aborted')

        refused = assert_raises(AccessDenied) do
          signicat.callback_phase(cancelled, stored_session)
        end

        assert_equal 'access_denied', refused.code
      end

      test 'a missing domain or an unknown level is a setup mistake, before anyone is sent away' do
        nowhere = signicat(domain: nil)
        unknown_level = signicat(loa: 'max')

        assert_raises(ArgumentError) { nowhere.request_phase(redirect_uri: CALLBACK_URL) }
        assert_raises(ArgumentError) { unknown_level.request_phase(redirect_uri: CALLBACK_URL) }
      end

      private

      def signicat(**settings)
        Signicat.new(client_id: 'app', client_secret: 'secret', domain: DOMAIN,
          idp: 'mitid', loa: 'substantial', **settings)
      end

      def auth(**claims)
        claims = {
          iss: ISSUER,
          aud: 'app',
          exp: 1.hour.from_now.to_i,
          nonce: 'n',
          sub: 'hashed-subject',
          idp: 'mitid',
          acr: 'substantial',
        }.merge(claims)
        stub_json(:post, TOKEN_URL, access_token: 'access', id_token: id_token(claims))

        signicat.callback_phase(callback_params, stored_session(nonce: 'n'))
      end
    end
  end
end
