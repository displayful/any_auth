# frozen_string_literal: true

require 'rails'
require 'action_controller/railtie'

class TestApp < Rails::Application
  config.root = __dir__
  config.eager_load = false
  config.secret_key_base = 'secret' * 8
  config.hosts.clear
  config.logger = Logger.new(nil)
  config.action_controller.allow_forgery_protection = false
end

TestApp.initialize!

TestApp.routes.draw do
  scope 'shops', controller: 'any_auth/fields_test/shops' do
    get 'new', action: :new
    post '/', action: :create
    get 'callback', action: :callback
  end

  scope ':provider', controller: 'any_auth/controller_helpers_test/sign_ins' do
    post 'leave', action: :create
    get 'home', action: :show
    get 'remembered', action: :remembered
  end
end
