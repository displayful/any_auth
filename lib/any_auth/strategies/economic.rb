module AnyAuth
  module Strategies
    class Economic < Base
      attribute :agreement_token, :string
      attribute :app_token, :string

      validates :agreement_token, :app_token, presence: true

      def authorization(credentials)
        {
          'X-AppSecretToken' => credentials['app_token'].to_s,
          'X-AgreementGrantToken' => credentials['agreement_token'].to_s,
        }
      end
    end
  end
end
