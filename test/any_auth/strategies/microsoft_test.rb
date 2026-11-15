# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class MicrosoftTest < ActiveSupport::TestCase
      TENANT = '72f988bf-86f1-41af-91ab-2d7cd011db47'
      PERSONAL = '9188040d-6c67-4c5b-b112-36a304b66dad'
      TOKEN_URL = 'https://login.microsoftonline.com/common/oauth2/v2.0/token'

      test 'a person is their tenant and object id, never their email' do
        assert_equal "#{TENANT}:o-1", auth(oid: 'o-1', email: 'mette@acme.test').uid
      end

      test 'a work tenant whose domain owner is verified confirms the email' do
        verified = auth(oid: 'o-1', email: 'mette@acme.test', xms_edov: true)
        unverified = auth(oid: 'o-1', email: 'mette@acme.test')

        assert_predicate verified.info, :email_verified
        assert_not unverified.info.email_verified
      end

      test 'a personal account never confirms the email, whatever it claims' do
        personal = auth(oid: 'o-1', email: 'mette@acme.test', xms_edov: true,
          tid: PERSONAL, iss: issuer(PERSONAL))

        assert_not personal.info.email_verified
      end

      test 'a token issued by another tenant than the one it names is refused' do
        assert_raises(InvalidCallback) { auth(oid: 'o-1', iss: issuer(PERSONAL)) }
      end

      test 'a tenant that is not a tenant id is refused' do
        assert_raises(InvalidCallback) { auth(oid: 'o-1', tid: 'common', iss: issuer('common')) }
      end

      private

      def issuer(tenant)
        "https://login.microsoftonline.com/#{tenant}/v2.0"
      end

      def auth(**claims)
        claims = {
          tid: TENANT,
          iss: issuer(TENANT),
          aud: 'app',
          exp: 1.hour.from_now.to_i,
          nonce: 'n',
        }.merge(claims)
        stub_json(:post, TOKEN_URL, access_token: 'access', id_token: id_token(claims))
        microsoft = Microsoft.new(client_id: 'app', client_secret: 'secret')

        microsoft.callback_phase(callback_params, stored_session(nonce: 'n'))
      end
    end
  end
end
