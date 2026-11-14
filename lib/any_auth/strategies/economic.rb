# frozen_string_literal: true

module AnyAuth
  module Strategies
    class Economic < Base
      attribute :agreement_token, :string
      attribute :app_token, :string

      validates :agreement_token, :app_token, presence: true
    end
  end
end
