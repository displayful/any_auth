module AnyAuth
  module Strategies
    class Developer < Base
      attribute :email, :string

      validates :email, presence: true

      def callback_phase(_params = {}, _session = nil)
        raise InvalidCallback, 'The developer sign-in needs an email' unless valid?

        address = email.strip.downcase

        Auth.new(provider:, uid: address, info: Info.new(email: address, email_verified: true), credentials: {})
      end
    end
  end
end
