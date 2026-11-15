# frozen_string_literal: true

require 'test_helper'
require 'test_app'

module AnyAuth
  class FailureRedirectTest < ActionDispatch::IntegrationTest
    class FailuresController < ActionController::Base
      include ControllerHelpers

      rescue_from AuthenticationError, with: :redirect_to_any_auth_failure

      def denied
        raise AccessDenied.new('google returned access_denied', code: 'access_denied')
      end

      def forged
        raise InvalidCallback, 'Invalid state'
      end

      def misconfigured
        raise ConfigurationError.new('google returned invalid_client', code: 'invalid_client')
      end

      def show
        render plain: "#{params[:provider]}: #{params[:message]}"
      end
    end

    test "a refusal goes to the failure page with the provider's code, and is reported" do
      assert_error_reported(AccessDenied) { get '/failing/google/denied' }

      assert_redirected_to '/auth/failure?message=access_denied&provider=google'
    end

    test 'a failure without a code is named by its kind' do
      get '/failing/google/forged'

      assert_redirected_to '/auth/failure?message=invalid_callback&provider=google'
    end

    test 'a setup mistake is not sent to the failure page; it is an error' do
      get '/failing/google/misconfigured'

      assert_response :internal_server_error
    end

    private

    def app
      TestApp
    end
  end
end
