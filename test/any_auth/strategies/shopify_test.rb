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
      HELD = { 'state' => '0.6784241404160823', 'redirect_uri' => 'https://tavle.test/callback' }.freeze

      test 'a shop is the myshopify.com address, however it is typed' do
        ['mystore', 'MyStore.myshopify.com', 'https://mystore.myshopify.com//', 'mystore.myshopify.com/admin',
         'https://admin.shopify.com/store/mystore/orders'].each do |typed|
          assert_equal 'mystore.myshopify.com', Shopify.new(shop: typed).shop
        end
      end

      test 'an address that is not a shop is an error on the shop' do
        shopify = Shopify.new(shop: 'evil.test/x')

        assert_not shopify.valid?
        assert_includes shopify.errors.attribute_names, :shop
      end

      test 'signing in happens at the shop itself' do
        request = Shopify.new(shop: 'mystore', client_id: 'app').request_phase(redirect_uri: 'https://tavle.test/callback')

        assert request.url.start_with?('https://mystore.myshopify.com/admin/oauth/authorize?')
      end

      test "a callback with Shopify's own signature for the shop is swapped for its tokens" do
        swap = stub_request(:post, 'https://some-shop.myshopify.com/admin/oauth/access_token')
               .with(body: hash_including('code' => SIGNED['code'], 'expiring' => '1'))
               .to_return(headers: { 'Content-Type' => 'application/json' },
                 body: { access_token: 'ny', refresh_token: 'igen' }.to_json)

        auth = Shopify.new(shop: 'some-shop', client_secret: 'hush').callback_phase(SIGNED, HELD)

        assert_requested swap
        assert_equal 'shopify', auth.provider
        assert_equal({ 'access_token' => 'ny', 'refresh_token' => 'igen' }, auth.credentials)
      end

      test 'a callback changed on the way, for another shop, or with no secret to check it by, is not ours' do
        ours = Shopify.new(shop: 'some-shop', client_secret: 'hush')

        assert_raises(InvalidCallback) { ours.callback_phase(SIGNED.merge('code' => 'changed'), HELD) }
        assert_raises(InvalidCallback) { ours.callback_phase(SIGNED, HELD.merge('state' => 'another')) }
        assert_raises(InvalidCallback) { Shopify.new(shop: 'some-shop').callback_phase(SIGNED, HELD) }
        assert_raises(InvalidCallback) do
          Shopify.new(shop: 'other-shop', client_secret: 'hush').callback_phase(SIGNED, HELD)
        end
      end
    end
  end
end
