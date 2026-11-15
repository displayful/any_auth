# frozen_string_literal: true

require 'test_helper'
require 'test_app'
require 'any_auth/strategies/developer'

module AnyAuth
  class ControllerHelpersTest < ActionDispatch::IntegrationTest
    class SignInsController < ActionController::Base
      include ControllerHelpers

      STRATEGIES = { 'hubspot' => Strategies::Hubspot, 'relatel' => Strategies::Relatel,
                     'developer' => Strategies::Developer }.freeze

      rescue_from(InvalidCallback) { head :unprocessable_content }

      def create
        strategy.assign_attributes(params.permit(:email))

        redirect_to_provider strategy,
          redirect_uri: 'https://tavle.test/home',
          params: { membership_id: 7 }
      end

      def show
        auth = authenticate_with_provider(strategy)

        render json: { uid: auth.uid, credentials: auth.credentials, params: auth.params }
      end

      def remembered
        render json: any_auth_params(strategy)
      end

      def forget
        delete_any_auth_cookie
        head :ok
      end

      private

      def strategy
        @strategy ||= STRATEGIES.fetch(params[:provider]).new.tap do |strategy|
          next unless strategy.respond_to?(:client_id=)

          strategy.assign_attributes(client_id: 'app', client_secret: 'secret')
        end
      end
    end

    setup do
      stub_json(:post, 'https://api.hubspot.com/oauth/2026-09/token', access_token: 'new')
      stub_json(:post, 'https://api.hubspot.com/oauth/2026-09/token/introspect',
        active: true, user_id: 41)
    end

    test 'leaving and coming home is one call each, and brings back what the app asked to keep' do
      post '/hubspot/leave'

      assert response.location.start_with?('https://app.hubspot.com/oauth/authorize?')

      get '/hubspot/home', params: { code: 'code', state: state_sent }

      assert_equal({ 'access_token' => 'new' }, response.parsed_body['credentials'])
      assert_equal({ 'membership_id' => 7 }, response.parsed_body['params'])
    end

    test 'a second sign-in replaces the first, whichever provider it is for' do
      post '/hubspot/leave'
      first = state_sent
      post '/relatel/leave'
      get '/hubspot/home', params: { code: 'code', state: first }

      assert_response :unprocessable_content
    end

    test 'with no sign-in under way there is nothing to read and nothing to come home to' do
      get '/hubspot/remembered'

      assert_empty response.parsed_body

      get '/hubspot/home', params: { code: 'code', state: 'x' }

      assert_response :unprocessable_content
    end

    test 'a sign-in the app forgot, as on signing out, cannot be finished' do
      post '/hubspot/leave'
      state = state_sent
      delete '/hubspot/forget'
      get '/hubspot/home', params: { code: 'code', state: }

      assert_response :unprocessable_content
    end

    test 'coming home a second time is not a sign-in' do
      post '/hubspot/leave'
      state = state_sent
      get '/hubspot/home', params: { code: 'code', state: }
      get '/hubspot/home', params: { code: 'code', state: }

      assert_response :unprocessable_content
    end

    test 'what one provider kept is no use to another' do
      post '/hubspot/leave'
      get '/relatel/home', params: { code: 'code' }

      assert_response :unprocessable_content
    end

    test 'what the app asked to remember can be read before anything is swapped, and stays' do
      post '/hubspot/leave'
      state = state_sent
      get '/hubspot/remembered'

      assert_equal({ 'membership_id' => 7 }, response.parsed_body)
      assert_not_requested :post, 'https://api.hubspot.com/oauth/2026-09/token'

      get '/hubspot/home', params: { code: 'code', state: }

      assert_response :success
    end

    test 'a sign-in left for more than ten minutes ago is gone' do
      post '/hubspot/leave'
      state = state_sent

      travel 11.minutes do
        get '/hubspot/remembered'

        assert_empty response.parsed_body

        get '/hubspot/home', params: { code: 'code', state: }

        assert_response :unprocessable_content
      end
    end

    test 'the fields a strategy was given come home with it, and never show in the address' do
      post '/developer/leave', params: { email: 'Mette@Acme.test' }

      assert_equal %w[state], query_of(response.location).keys

      get '/developer/home', params: { state: state_sent }

      assert_equal 'mette@acme.test', response.parsed_body['uid']
    end

    test 'over HTTPS the sign-in under way is kept in a cookie a provider can POST back to' do
      https!
      post '/hubspot/leave'

      kept = set_cookie('__Host-any_auth')

      assert_match(/; secure/i, kept)
      assert_match(/; samesite=none/i, kept)
      assert_match(/; httponly/i, kept)
      assert_match(%r{; path=/(;|\z)}i, kept)
      assert_no_match(/; domain=/i, kept)

      get '/hubspot/home', params: { code: 'code', state: state_sent }
      deleted = set_cookie('__Host-any_auth')

      assert_response :success
      assert_match(/; secure/i, deleted)
    end

    test "nothing about a sign-in is kept in the app's own session" do
      post '/hubspot/leave'

      assert_empty session.to_hash.except('session_id')
    end

    test 'a provider that answers in a POST body is read the same way' do
      post '/developer/leave', params: { email: 'Mette@Acme.test' }

      post '/developer/home', params: { state: state_sent }

      assert_equal 'mette@acme.test', response.parsed_body['uid']
    end

    private

    def app
      TestApp
    end

    def set_cookie(name)
      Array(response.headers['Set-Cookie']).join("\n").lines.find { it.start_with?("#{name}=") }
    end

    def state_sent
      query_of(response.location)['state']
    end
  end
end
