module AnyAuth
  module Strategies
    class Developer < Base
      attribute :email, :string

      def request_phase(redirect_uri:, **)
        session = { 'state' => SecureRandom.hex(24) }

        Request.new(url: "#{redirect_uri}?#{{ email:, state: session['state'] }.to_query}", session:)
      end

      def callback_phase(params, session)
        state = session.to_h['state']
        address = params['email'].to_s.strip.downcase

        unless state.present? && ActiveSupport::SecurityUtils.secure_compare(state, params['state'].to_s)
          raise InvalidCallback, 'No developer sign-in is under way'
        end
        raise InvalidCallback, 'The developer sign-in needs an email' if address.blank?

        Auth.new(provider:, uid: address, info: Info.new(email: address, email_verified: true), credentials: {})
      end
    end
  end
end
