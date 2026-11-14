require 'test_helper'

module AnyAuth
  module Strategies
    class RelatelTest < ActiveSupport::TestCase
      test 'Relatel names the employee who signed in, and says which company they belong to' do
        stub_json(:post, 'https://app.relatel.dk/api/v2/token', access_token: 'ny')
        stub_json(:get, 'https://app.relatel.dk/api/v2/employee',
          employee: { id: 34, name: 'Mette Holm', company_id: 8823 })

        auth = Relatel.new(client_id: 'app', client_secret: 'tys').callback_phase({ 'code' => 'kode', 'state' => 's' },
          { 'state' => 's', 'redirect_uri' => 'https://tavle.test/callback' })

        assert_equal '34', auth.uid
        assert_equal 'Mette Holm', auth.info.name
        assert_equal 8823, auth.raw['company_id']
        assert_requested :get, 'https://app.relatel.dk/api/v2/employee', headers: { 'Authorization' => 'Bearer ny' }
      end
    end
  end
end
