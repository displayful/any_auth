# frozen_string_literal: true

require 'test_helper'
require 'test_app'

module AnyAuth
  class FieldsTest < ActionDispatch::IntegrationTest
    class ShopsController < ActionController::Base
      include ControllerHelpers

      FORM = <<~ERB
        <%= form_with model: @strategy, scope: :strategy, url: '/shops' do |form| %>
          <%= form.label :shop %>
          <%= form.text_field :shop %>
          <%= tag.p @strategy.errors.full_messages_for(:shop).to_sentence %>
          <%= form.submit 'Connect' %>
        <% end %>
      ERB

      def new
        @strategy = strategy
        render inline: FORM
      end

      def create
        @strategy = strategy(params.expect(strategy: %i[shop]))

        if @strategy.valid?
          redirect_to_provider @strategy, redirect_uri: 'https://tavle.test/shops/callback'
        else
          render inline: FORM, status: :unprocessable_content
        end
      end

      def callback
        shopify = strategy
        auth = authenticate_with_provider(shopify)

        render json: shopify.attributes.merge(auth.credentials)
      end

      private

      def strategy(fields = {})
        shopify = Strategies::Shopify.new(client_id: 'app', client_secret: 'hush')
        shopify.assign_attributes(fields)
        shopify
      end
    end

    test 'the fields a strategy asks for are a form like any other' do
      get '/shops/new'

      assert_select 'input[name=?]', 'strategy[shop]'
    end

    test 'what was typed wrongly comes back with its error, and nobody leaves' do
      post '/shops', params: { strategy: { shop: 'evil.test/x' } }

      assert_response :unprocessable_content
      assert_select 'input[name=?][value=?]', 'strategy[shop]', 'evil.test'
      assert_select 'p', /Shop is invalid/
    end

    test 'the fields travel with the request and are stored with the tokens' do
      post '/shops', params: { strategy: { shop: 'mystore' } }
      state = query_of(response.location)['state']
      answer = { 'code' => 'kode', 'shop' => 'mystore.myshopify.com', 'state' => state }
      hmac = OpenSSL::HMAC.hexdigest('SHA256', 'hush', answer.sort.map { it.join('=') }.join('&'))
      stub_json(:post, 'https://mystore.myshopify.com/admin/oauth/access_token', access_token: 'ny')

      get '/shops/callback', params: answer.merge('hmac' => hmac)

      assert_equal 'mystore.myshopify.com', response.parsed_body['shop']
      assert_equal 'ny', response.parsed_body['access_token']
    end

    private

    def app
      TestApp
    end
  end
end
