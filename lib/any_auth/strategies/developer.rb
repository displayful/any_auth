module AnyAuth
  module Strategies
    class Developer < Base
      attribute :email, :string

      validates :email, presence: true

      def request_phase(redirect_uri:, **)
        session = { 'state' => SecureRandom.hex(24) }
        home = URI(redirect_uri)
        home.query = { email:, state: session['state'] }.to_query

        Request.new(url: home.to_s, session:)
      end

      def callback_phase(params, session)
        address = params['email'].to_s.strip.downcase

        raise InvalidCallback, 'No developer sign-in is under way' unless same?(session.to_h['state'], params['state'])
        raise InvalidCallback, 'The developer sign-in needs an email' if address.blank?

        Auth.new(provider:, uid: address, credentials: {}, info: Info.new(email: address, email_verified: true))
      end
    end
  end
end
