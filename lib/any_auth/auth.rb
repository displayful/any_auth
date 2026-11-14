module AnyAuth
  Auth = Data.define(:provider, :uid, :info, :credentials, :raw) do
    def initialize(provider:, credentials:, uid: nil, info: nil, raw: {})
      super
    end
  end
end
