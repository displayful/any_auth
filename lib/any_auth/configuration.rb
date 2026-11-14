# frozen_string_literal: true

module AnyAuth
  class Configuration
    def initialize
      @entries = {}
    end

    def provider(name, strategy: nil, from: nil, **options)
      if from
        strategy ||= strategy_class(from)
        options = entry_for(from)[:options].merge(options)
      end

      @entries[name.to_s] = { strategy_class: class_named(strategy || name), options: }
    end

    def providers
      @entries.keys
    end

    def strategy_class(name)
      entry_for(name)[:strategy_class]
    end

    def strategy(name, attributes = {})
      strategy = strategy_class(name).new(defaults_for(name))
      strategy.assign_attributes(attributes)
      strategy.provider = name.to_s
      strategy
    end

    private

    def entry_for(name)
      @entries.fetch(name.to_s)
    end

    def class_named(strategy)
      return strategy if strategy.is_a?(Class)

      Strategies.const_get(strategy.to_s.underscore.camelize, false)
    end

    def defaults_for(name)
      entry_for(name)[:options].transform_values { resolve(it) }
    end

    def resolve(value)
      return value.call if value.respond_to?(:call)

      value
    end
  end
end
