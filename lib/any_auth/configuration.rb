module AnyAuth
  class Configuration
    def initialize
      @entries = {}
    end

    def provider(name, strategy: nil, from: nil, **options)
      raise ArgumentError, "#{name} cannot be made from itself" if from.to_s == name.to_s

      @entries[name.to_s] = { strategy:, from: from&.to_s, options: }
    end

    def providers
      @entries.keys
    end

    def strategy_class(name)
      entry = entry_for(name)
      return strategy_class(entry[:from]) if entry[:from] && entry[:strategy].nil?

      named = entry[:strategy] || name

      named.is_a?(Class) ? named : Strategies.const_get(named.to_s.underscore.camelize, false)
    end

    def strategy(name, **overrides)
      options = options_for(name).merge(overrides).transform_values { it.respond_to?(:call) ? it.call : it }

      strategy_class(name).new(**options, provider: name.to_s)
    end

    private

    def entry_for(name)
      @entries.fetch(name.to_s)
    end

    def options_for(name)
      entry = entry_for(name)

      (entry[:from] ? options_for(entry[:from]) : {}).merge(entry[:options])
    end
  end
end
