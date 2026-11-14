module AnyAuth
  class Configuration
    def initialize
      @entries = {}
    end

    def provider(name, strategy: nil, from: nil, **options)
      inherited = from ? entry_for(from) : { options: {} }
      strategy_class = class_named(strategy || inherited[:strategy_class] || name)

      @entries[name.to_s] = { strategy_class:, options: inherited[:options].merge(options) }
    end

    def providers
      @entries.keys
    end

    def strategy_class(name)
      entry_for(name)[:strategy_class]
    end

    def strategy(name, attributes = {})
      strategy_class(name).new(defaults_for(name)).tap do |strategy|
        strategy.assign_attributes(attributes)
        strategy.provider = name.to_s
      end
    end

    private

    def entry_for(name)
      @entries.fetch(name.to_s)
    end

    def class_named(strategy)
      strategy.is_a?(Class) ? strategy : Strategies.const_get(strategy.to_s.underscore.camelize, false)
    end

    def defaults_for(name)
      entry_for(name)[:options].transform_values { it.respond_to?(:call) ? it.call : it }
    end
  end
end
