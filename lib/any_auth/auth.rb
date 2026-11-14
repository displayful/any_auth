module AnyAuth
  Auth = Data.define(:provider, :uid, :info, :credentials, :raw) do
    def initialize(provider:, credentials:, uid: nil, info: Info.new, raw: {})
      super
    end
  end
end
