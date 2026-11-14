require 'test_helper'
require 'action_controller'

module AnyAuth
  class ConfigurationTest < ActiveSupport::TestCase
    setup do
      @config = Configuration.new
      @config.provider :google, client_id: 'sign-in-app', client_secret: 'tys'
    end

    test 'a provider is built from its entry, and answers to its name' do
      google = @config.strategy(:google)

      assert_instance_of Strategies::Google, google
      assert_equal 'google', google.provider
      assert_equal 'sign-in-app', google.client_id
    end

    test 'an entry made from another shares its client and asks for something else' do
      @config.provider :google_sheets, from: :google, scope: 'drive.file', access_type: 'offline'

      sheets = @config.strategy(:google_sheets)
      asked = query_of(sheets.request_phase(redirect_uri: CALLBACK_URL).url)

      assert_equal 'google_sheets', sheets.provider
      assert_equal 'sign-in-app', asked['client_id']
      assert_equal 'openid drive.file', asked['scope']
      assert_equal 'offline', asked['access_type']
    end

    test 'an entry naming only the strategy shares nothing but the code' do
      @config.provider 'google-sheets', strategy: :google, scope: 'drive.file'

      sheets = @config.strategy('google-sheets', client_id: 'sheets-app')

      assert_instance_of Strategies::Google, sheets
      assert_equal 'sheets-app', sheets.client_id
      assert_nil sheets.client_secret
    end

    test 'what is passed when building wins, and a callable is asked then' do
      clients = %w[first second]
      @config.provider :hubspot, client_id: -> { clients.shift }, scope: 'deals'

      assert_equal 'first', @config.strategy(:hubspot).client_id
      assert_equal 'second', @config.strategy(:hubspot).client_id
      assert_equal 'mine', @config.strategy(:hubspot, client_id: 'mine').client_id
    end

    test 'fields are attributes of the strategy' do
      @config.provider :shopify, scope: 'read_orders'

      assert_equal 'mystore.myshopify.com', @config.strategy(:shopify, shop: 'mystore').shop
    end

    test 'fields come straight from permitted parameters, and only from permitted ones' do
      @config.provider :shopify, scope: 'read_orders'
      typed = { shop: 'mystore', client_secret: 'theirs' }
      posted = ActionController::Parameters.new(strategy: typed)

      shopify = @config.strategy(:shopify, posted.expect(strategy: %i[shop]))

      assert_equal 'mystore.myshopify.com', shopify.shop
      assert_nil shopify.client_secret
      assert_raises(ActiveModel::ForbiddenAttributesError) do
        @config.strategy(:shopify, posted[:strategy])
      end
    end

    test 'a name nobody configured is an error, and is not listed' do
      assert_equal %w[google], @config.providers
      assert_raises(KeyError) { @config.strategy(:okta) }
    end

    test 'a provider keeps the name it was configured under' do
      assert_equal 'google', @config.strategy(:google, provider: 'another').provider
    end

    test 'an option the strategy does not have is an error' do
      unknown = ActiveModel::UnknownAttributeError

      assert_raises(unknown) { @config.strategy(:google, scoop: 'email') }
      assert_raises(unknown) { @config.strategy(:google, authorize_options: [:scoop]) }
    end

    test 'a provider that is no strategy, or made from one nobody configured, is refused at once' do
      assert_raises(NameError) { @config.provider :file }
      assert_raises(KeyError) { @config.provider :sheets, from: :nobody }
    end
  end
end
