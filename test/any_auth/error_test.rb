# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  class ErrorTest < ActiveSupport::TestCase
    test "the reason is the vendor's own code" do
      assert_equal 'invalid_grant', AccessDenied.new(code: 'invalid_grant').reason
    end

    test 'without a code, the reason is the kind of failure' do
      assert_equal 'invalid_callback', InvalidCallback.new.reason
      assert_equal 'unavailable', Unavailable.new.reason
    end
  end
end
