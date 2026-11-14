module AnyAuth
  module Strategies
    class Adversus < Base
      attribute :username, :string
      attribute :password, :string

      validates :username, :password, presence: true

      def authorization(credentials)
        { 'Authorization' => "Basic #{[credentials.values_at('username', 'password').join(':')].pack('m0')}" }
      end
    end
  end
end
