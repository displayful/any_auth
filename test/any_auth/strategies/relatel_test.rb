require 'test_helper'

module AnyAuth
  module Strategies
    class RelatelTest < ActiveSupport::TestCase
      EMPLOYEE_URL = 'https://app.relatel.dk/api/v2/employee'.freeze

      test 'Relatel names the employee who signed in, and says which company they belong to' do
        stub_json(:post, 'https://app.relatel.dk/api/v2/token', access_token: 'ny')
        stub_json(:get, EMPLOYEE_URL, employee: { id: 34, name: 'Mette Holm', company_id: 8823 })
        relatel = Relatel.new(client_id: 'app', client_secret: 'tys')

        auth = relatel.callback_phase(callback_params, stored_session)

        assert_equal '34', auth.uid
        assert_equal 'Mette Holm', auth.info.name
        assert_equal 8823, auth.raw['company_id']
        assert_requested :get, EMPLOYEE_URL, headers: { 'Authorization' => 'Bearer ny' }
      end
    end
  end
end
