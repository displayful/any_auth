module AnyAuth
  module Strategies
    class Developer < Base
      attribute :email, :string

      validates :email, presence: true

      def request_phase(redirect_uri:)
        session = { 'state' => SecureRandom.hex(24) }
        home = URI(redirect_uri)
        home.query = [home.query, { state: session['state'] }.to_query].compact.join('&')

        Request.new(url: home.to_s, session:)
      end

      def callback_phase(params, session)
        raise InvalidCallback, 'No developer sign-in is under way' unless same?(session.to_h['state'], params['state'])
        raise InvalidCallback, 'The developer sign-in needs an email' unless valid?

        address = email.strip.downcase

        Auth.new(provider:, uid: address, credentials: {}, info: Info.new(email: address, email_verified: true))
      end
    end
  end
end
