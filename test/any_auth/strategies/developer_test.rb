require 'test_helper'
require 'any_auth/strategies/developer'

module AnyAuth
  module Strategies
    class DeveloperTest < ActiveSupport::TestCase
      test 'a developer has to say who they are before leaving' do
        assert_predicate Developer.new(email: 'mette@acme.test'), :valid?
        assert_includes Developer.new.tap(&:valid?).errors.attribute_names, :email
      end

      test 'a developer comes straight home as whoever they say they are' do
        developer = Developer.new(email: ' Mette@Acme.test ')
        request = developer.request_phase(redirect_uri: 'https://tavle.test/home?tenant=7')
        sent = query_of(request.url)

        auth = developer.callback_phase(sent, request.session)

        assert_equal 'developer', auth.provider
        assert_equal 'mette@acme.test', auth.uid
        assert_predicate auth.info, :email_verified
        assert_equal '7', sent['tenant']
        assert_nil sent['email']
      end

      test 'a callback nobody started here, or naming nobody, is not a sign-in' do
        developer = Developer.new(email: 'a@b.test')
        request = developer.request_phase(redirect_uri: 'https://tavle.test/home')
        sent = query_of(request.url)

        assert_raises(InvalidCallback) { developer.callback_phase(sent, nil) }
        assert_raises(InvalidCallback) { developer.callback_phase(sent.merge('state' => 'forged'), request.session) }
        assert_raises(InvalidCallback) { Developer.new.callback_phase(sent, request.session) }
      end
    end
  end
end
