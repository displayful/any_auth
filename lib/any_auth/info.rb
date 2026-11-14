# frozen_string_literal: true

module AnyAuth
  Info = Data.define(:name, :email, :email_verified, :image) do
    def initialize(name: nil, email: nil, email_verified: false, image: nil)
      super
    end
  end
end
