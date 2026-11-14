# frozen_string_literal: true

module AnyAuth
  module Strategies
    class OpenIDConnect < OAuth
      self.pkce = true

      def request_phase(redirect_uri:, scope: self.scope || 'email profile', **params)
        nonce = SecureRandom.hex(16)
        request = super(redirect_uri:, **params, scope: openid_scope(scope), nonce:)

        request.with(session: request.session.merge('nonce' => nonce))
      end

      private

      def openid_scope(scope)
        ['openid', *scope.split].uniq.join(' ')
      end

      def identity(access_token, session)
        claims = decode_id_token(access_token)
        raise Unauthorized, 'Invalid ID token' unless valid_claims?(claims, session)

        identity_from(claims).merge(raw: claims)
      end

      def decode_id_token(access_token)
        claims = JWT.decode(access_token.params['id_token'], nil, false).first
        raise Unauthorized, 'Invalid ID token' unless claims.is_a?(Hash)

        claims
      rescue JWT::DecodeError
        raise Unauthorized, 'Invalid ID token'
      end

      def identity_from(claims)
        { uid: fetch_claim(claims, 'sub'), info: info_from(claims) }
      end

      def info_from(claims)
        Info.new(name: claims['name'], email: claims['email'], image: claims['picture'])
      end

      def valid_claims?(claims, session)
        valid_issuer?(claims) && valid_audience?(claims) && unexpired?(claims) &&
          valid_nonce?(claims, session)
      end

      def valid_issuer?(_claims)
        raise NotImplementedError, "#{self.class.name} must define valid_issuer?(claims)"
      end

      def valid_audience?(claims)
        audiences = Array(claims['aud'])
        authorized_party = claims['azp']

        client_id.present? && audiences.include?(client_id) &&
          authorized_party.in?([nil, client_id]) &&
          (audiences.one? || authorized_party == client_id)
      end

      def unexpired?(claims)
        claims['exp'].is_a?(Numeric) && Time.at(claims['exp']).future?
      end

      def valid_nonce?(claims, session)
        secure_compare(session['nonce'], claims['nonce'])
      end

      def fetch_claim(claims, name)
        value = claims[name]
        raise Unauthorized, "Missing #{name} claim" unless value.is_a?(String) && value.present?

        value
      end
    end
  end
end
