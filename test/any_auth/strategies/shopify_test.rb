# frozen_string_literal: true

require 'test_helper'

module AnyAuth
  module Strategies
    class ShopifyTest < ActiveSupport::TestCase
      SIGNED = {
        'code' => '0907a61c0c8d55e99db179b68161bc00',
        'shop' => 'some-shop.myshopify.com',
        'state' => '0.6784241404160823',
        'timestamp' => '1337178173',
        'hmac' => '700e2dadb827fcc8609e9d5ce208b2e9cdaab9df07390d2cbca10d7c328fc4bf',
      }.freeze
      STORED = { 'state' => '0.6784241404160823', 'redirect_uri' => CALLBACK_URL }.freeze
      TOKEN_URL = 'https://some-shop.myshopify.com/admin/oauth/access_token'

      test 'a shop is the myshopify.com address, however it is typed' do
        typed = [
          'mystore',
          'MyStore.myshopify.com',
          'https://mystore.myshopify.com//',
          'mystore.myshopify.com/admin',
          'https://admin.shopify.com/store/mystore/orders',
        ]

        typed.each { assert_equal 'mystore.myshopify.com', Shopify.new(shop: it).shop }
      end

      test 'an address that is not a shop is an error on the shop' do
        shopify = Shopify.new(shop: 'evil.test/x')

        assert_not shopify.valid?
        assert_includes shopify.errors.attribute_names, :shop
      end

      test 'a shop that is not a shop is never sent anywhere' do
        elsewhere = Shopify.new(shop: 'evil.test', client_id: 'app')
        nowhere = Shopify.new(client_id: 'app')

        assert_raises(ArgumentError) { elsewhere.request_phase(redirect_uri: CALLBACK_URL) }
        assert_raises(ArgumentError) { nowhere.request_phase(redirect_uri: CALLBACK_URL) }
      end

      test 'signing in happens at the shop itself' do
        shopify = Shopify.new(shop: 'mystore', client_id: 'app')

        request = shopify.request_phase(redirect_uri: CALLBACK_URL)

        assert request.url.start_with?('https://mystore.myshopify.com/admin/oauth/authorize?')
      end

      test "a callback with Shopify's own signature for the shop is swapped for its tokens" do
        stub_json(:post, TOKEN_URL, access_token: 'new', refresh_token: 'refresh')

        auth = shop.callback_phase(SIGNED, STORED)

        assert_equal 'shopify', auth.provider
        assert_equal 'some-shop.myshopify.com', auth.uid
        assert_equal({ 'access_token' => 'new', 'refresh_token' => 'refresh' }, auth.credentials)
        assert_requested :post, TOKEN_URL, body: hash_including(
          'code' => SIGNED['code'],
          'expiring' => '1'
        )
      end

      test 'a callback changed on the way is not ours' do
        changed = SIGNED.merge('code' => 'changed')
        nested = SIGNED.merge('code' => [SIGNED['code']])

        assert_raises(InvalidCallback) { shop.callback_phase(changed, STORED) }
        assert_raises(InvalidCallback) { shop.callback_phase(nested, STORED) }
        assert_raises(InvalidCallback) { shop.callback_phase(SIGNED, STORED.merge('state' => 'x')) }
      end

      test 'a callback for another shop, or checked by another secret or none, is not ours' do
        another_shop = Shopify.new(shop: 'other-shop', client_secret: 'hush')
        another_secret = Shopify.new(shop: 'some-shop', client_secret: 'another')
        no_secret = Shopify.new(shop: 'some-shop')

        assert_raises(InvalidCallback) { another_shop.callback_phase(SIGNED, STORED) }
        assert_raises(InvalidCallback) { another_secret.callback_phase(SIGNED, STORED) }
        assert_raises(InvalidCallback) { no_secret.callback_phase(SIGNED, STORED) }
      end

      private

      def shop
        Shopify.new(shop: 'some-shop', client_secret: 'hush')
      end
    end
  end
end
