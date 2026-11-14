module AnyAuth
  PKCE = Data.define(:verifier, :challenge) do
    def self.pair
      verifier = SecureRandom.urlsafe_base64(64)

      new(verifier:, challenge: Digest::SHA256.base64digest(verifier).tr('+/', '-_').delete('='))
    end
  end
end
