require 'test_helper'
require 'test_app'

module AnyAuth
  class ControllerHelpersTest < ActionDispatch::IntegrationTest
    class SignInsController < ActionController::Base
      include ControllerHelpers

      rescue_from(InvalidCallback) { head :unprocessable_content }

      def create
        redirect_to_provider strategy, redirect_uri: 'https://tavle.test/home', membership_id: 7
      end

      def show
        render json: authenticate_with_provider(strategy).credentials
      end

      def stored
        render json: take_auth_request(params[:provider])
      end

      private

      def strategy
        Strategies.const_get(params[:provider].camelize, false).new(client_id: 'app', client_secret: 'tys')
      end
    end

    setup do
      stub_request(:post, 'https://api.hubapi.com/oauth/v1/token')
        .to_return(headers: { 'Content-Type' => 'application/json' }, body: { access_token: 'ny' }.to_json)
      stub_request(:get, 'https://api.hubapi.com/oauth/v1/access-tokens/ny')
        .to_return(headers: { 'Content-Type' => 'application/json' }, body: { hub_id: 8823 }.to_json)
    end

    test 'leaving for a provider and coming home is one call each' do
      post '/hubspot/leave'
      state = Rack::Utils.parse_query(URI(response.location).query)['state']

      assert response.location.start_with?('https://app.hubspot.com/oauth/authorize?')
      assert_match(/any_auth\.hubspot=.*httponly/i, response.headers['Set-Cookie'])

      get '/hubspot/home', params: { code: 'kode', state: }

      assert_equal({ 'access_token' => 'ny' }, response.parsed_body)

      get '/hubspot/home', params: { code: 'kode', state: }

      assert_response :unprocessable_content
    end

    test 'a request that left for one provider is no use to another' do
      post '/hubspot/leave'
      get '/relatel/home', params: { code: 'kode' }

      assert_response :unprocessable_content
    end

    test 'what the app stored with the request comes back with it' do
      post '/hubspot/leave'
      get '/hubspot/stored'

      assert_equal 7, response.parsed_body['membership_id']
      assert_equal 'https://tavle.test/home', response.parsed_body.dig('request', 'redirect_uri')
    end

    test 'a request older than ten minutes is gone' do
      post '/hubspot/leave'
      state = Rack::Utils.parse_query(URI(response.location).query)['state']

      travel 11.minutes do
        get '/hubspot/home', params: { code: 'kode', state: }

        assert_response :unprocessable_content
      end
    end

    private

    def app
      TestApp
    end
  end
end
