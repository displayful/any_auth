module AnyAuth
  module Strategies
    class Adversus < Base
      attribute :username, :string
      attribute :password, :string

      validates :username, :password, presence: true
    end
  end
end
