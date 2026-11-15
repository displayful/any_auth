# frozen_string_literal: true

require 'base64'
require 'digest'
require 'json'
require 'openssl'
require 'securerandom'
require 'time'
require 'uri'

require 'active_model'
require 'active_support'
require 'active_support/core_ext'
require 'active_support/security_utils'
require 'faraday'
require 'jwt'
require 'oauth2'

module AnyAuth
  class Error < StandardError
    attr_reader :code

    def initialize(message = nil, code: nil)
      @code = code
      super(message)
    end
  end

  class InvalidCallback < Error; end
  class Unauthorized < Error; end
  class Unavailable < Error; end
  class RateLimited < Unavailable; end

  class Declined < Error
    def initialize(code)
      super("Sign-in declined (#{code})", code:)
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield configuration
  end

  def self.providers
    configuration.providers
  end

  def self.strategy_class(name)
    configuration.strategy_class(name)
  end

  def self.strategy(...)
    configuration.strategy(...)
  end
end

require_relative 'any_auth/version'
require_relative 'any_auth/auth'
require_relative 'any_auth/configuration'
require_relative 'any_auth/info'
require_relative 'any_auth/pkce'
require_relative 'any_auth/request'
require_relative 'any_auth/controller_helpers'
require_relative 'any_auth/strategies/base'
require_relative 'any_auth/strategies/oauth2'
require_relative 'any_auth/strategies/open_id_connect'
require_relative 'any_auth/strategies/adversus'
require_relative 'any_auth/strategies/apple'
require_relative 'any_auth/strategies/economic'
require_relative 'any_auth/strategies/google'
require_relative 'any_auth/strategies/hubspot'
require_relative 'any_auth/strategies/microsoft'
require_relative 'any_auth/strategies/relatel'
require_relative 'any_auth/strategies/shopify'
require_relative 'any_auth/strategies/tavle'
