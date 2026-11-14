require 'test_helper'

module AnyAuth
  module Strategies
    class MicrosoftTest < ActiveSupport::TestCase
      TENANT = '72f988bf-86f1-41af-91ab-2d7cd011db47'
      PERSONAL = '9188040d-6c67-4c5b-b112-36a304b66dad'

      test 'a person is their tenant and object id, never their email' do
        assert_equal "#{TENANT}:o-1", auth(oid: 'o-1', email: 'mette@acme.test').uid
      end

      test 'only a verified domain owner in a work tenant confirms the email' do
        assert_predicate auth(oid: 'o-1', email: 'mette@acme.test', xms_edov: true).info, :email_verified
        assert_not auth(oid: 'o-1', email: 'mette@acme.test').info.email_verified
        assert_not auth(oid: 'o-1', email: 'mette@acme.test', xms_edov: true, tid: PERSONAL,
          iss: "https://login.microsoftonline.com/#{PERSONAL}/v2.0").info.email_verified
      end

      test 'a token issued by another tenant than the one it names is refused' do
        assert_raises(Unauthorized) do
          auth(oid: 'o-1', iss: "https://login.microsoftonline.com/#{PERSONAL}/v2.0")
        end
      end

      test 'a tenant that is not a tenant id is refused' do
        assert_raises(Unauthorized) do
          auth(oid: 'o-1', tid: 'common', iss: 'https://login.microsoftonline.com/common/v2.0')
        end
      end

      private

      def auth(**overrides)
        payload = {
          tid: TENANT,
          iss: "https://login.microsoftonline.com/#{TENANT}/v2.0",
          aud: 'app',
          exp: 1.hour.from_now.to_i,
          nonce: 'n',
        }.merge(overrides)
        stub_request(:post, 'https://login.microsoftonline.com/common/oauth2/v2.0/token')
          .with(body: hash_including('code_verifier' => 'v'))
          .to_return(headers: { 'Content-Type' => 'application/json' },
            body: { access_token: 'adgang', id_token: JWT.encode(payload, nil, 'none') }.to_json)

        Microsoft.new(client_id: 'app', client_secret: 'tys').callback_phase({ 'code' => 'kode', 'state' => 's' },
          { 'state' => 's', 'nonce' => 'n', 'code_verifier' => 'v', 'redirect_uri' => 'https://tavle.test/callback' })
      end
    end
  end
end
