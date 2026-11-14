require 'test_helper'

module AnyAuth
  module Strategies
    class MicrosoftTest < ActiveSupport::TestCase
      TENANT = '72f988bf-86f1-41af-91ab-2d7cd011db47'.freeze
      PERSONAL = '9188040d-6c67-4c5b-b112-36a304b66dad'.freeze

      test 'a person is their tenant and object id, never their email' do
        assert_equal "#{TENANT}:o-1", auth(oid: 'o-1', email: 'mette@acme.test').uid
      end

      test 'a work tenant whose domain owner is verified confirms the email' do
        assert_predicate auth(oid: 'o-1', email: 'mette@acme.test', xms_edov: true).info, :email_verified
        assert_not auth(oid: 'o-1', email: 'mette@acme.test').info.email_verified
      end

      test 'a personal account never confirms the email, whatever it claims' do
        personal = auth(oid: 'o-1', email: 'mette@acme.test', xms_edov: true, tid: PERSONAL,
          iss: "https://login.microsoftonline.com/#{PERSONAL}/v2.0")

        assert_not personal.info.email_verified
      end

      test 'a token issued by another tenant than the one it names is refused' do
        assert_raises(Unauthorized) { auth(oid: 'o-1', iss: "https://login.microsoftonline.com/#{PERSONAL}/v2.0") }
      end

      test 'a tenant that is not a tenant id is refused' do
        assert_raises(Unauthorized) do
          auth(oid: 'o-1', tid: 'common', iss: 'https://login.microsoftonline.com/common/v2.0')
        end
      end

      private

      def auth(**claims)
        claims = { tid: TENANT, iss: "https://login.microsoftonline.com/#{TENANT}/v2.0", aud: 'app',
                   exp: 1.hour.from_now.to_i, nonce: 'n' }.merge(claims)
        stub_json(:post, 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
          access_token: 'adgang', id_token: id_token(claims))

        Microsoft.new(client_id: 'app', client_secret: 'tys').callback_phase({ 'code' => 'kode', 'state' => 's' },
          { 'state' => 's', 'nonce' => 'n', 'redirect_uri' => 'https://tavle.test/callback' })
      end
    end
  end
end
