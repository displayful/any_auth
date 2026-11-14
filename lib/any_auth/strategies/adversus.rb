module AnyAuth
  module Strategies
    class Adversus < Base
      attribute :username, :string
      attribute :password, :string

      validates :username, :password, presence: true

      def authorization(credentials)
        login = credentials.values_at('username', 'password').join(':')

        { 'Authorization' => "Basic #{Base64.strict_encode64(login)}" }
      end
    end
  end
end
