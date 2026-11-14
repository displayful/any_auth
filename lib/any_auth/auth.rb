module AnyAuth
  Auth = Data.define(:provider, :uid, :info, :credentials, :raw, :params) do
    def initialize(provider:, credentials:, uid: nil, info: Info.new, raw: {}, params: {})
      super
    end
  end
end
