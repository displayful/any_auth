module AnyAuth
  PKCE = Data.define(:verifier, :challenge) do
    def self.pair
      verifier = SecureRandom.urlsafe_base64(64)
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

      new(verifier:, challenge:)
    end
  end
end
