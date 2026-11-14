# frozen_string_literal: true

module AnyAuth
  Auth = Data.define(:provider, :uid, :info, :credentials, :raw, :params) do
    def initialize(provider:, credentials:, uid: nil, info: Info.new, raw: {}, params: {})
      super
    end

    def inspect
      "#<data #{self.class.name} provider=#{provider.inspect}, uid=#{uid.inspect}>"
    end
  end
end
