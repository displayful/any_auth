# frozen_string_literal: true

require 'test_helper'
require 'pp'

module AnyAuth
  class AuthTest < ActiveSupport::TestCase
    test 'an auth never prints or serialises its tokens' do
      credentials = { 'access_token' => 'secret-token' }
      auth = Auth.new(provider: 'google', uid: 'g-1', credentials:)

      assert_not_includes auth.inspect, 'secret-token'
      assert_not_includes auth.pretty_inspect, 'secret-token'
      assert_not_includes auth.to_json, 'secret-token'
      assert_includes auth.to_json, 'g-1'
    end

    test 'a request never prints what it keeps in the session' do
      session = { 'code_verifier' => 'kept' }
      request = Request.new(url: 'https://vendor.test/authorize', session:)

      assert_not_includes request.inspect, 'kept'
      assert_not_includes request.pretty_inspect, 'kept'
    end
  end
end
