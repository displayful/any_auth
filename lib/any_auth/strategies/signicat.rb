# frozen_string_literal: true

module AnyAuth
  module Strategies
    class Signicat < OpenIDConnect
      LEVELS = %w[unspecified low substantial high].freeze

      authorize_option :prompt, :login_hint, :ui_locales

      attr_accessor :domain, :idp, :loa

      def request_phase(redirect_uri:, scope: self.scope || 'profile', **params)
        raise ArgumentError, "#{provider} needs a domain" if domain.blank?
        raise ArgumentError, "#{loa.inspect} is not a level: #{LEVELS.join(', ')}" unless valid_loa?

        super
      end

      def client_options
        site = URI::HTTPS.build(host: domain).to_s

        {
          site:,
          authorize_url: '/auth/open/connect/authorize',
          token_url: '/auth/open/connect/token',
        }
      end

      private

      def authorize_params
        super.merge(acr_values:).compact_blank
      end

      def acr_values
        values = []
        values << "idp:#{idps.join(',')}" if idps.any?
        values << "loa:#{loa}" if loa.present?

        values.join(' ')
      end

      def idps
        Array(idp)
      end

      def valid_loa?
        loa.blank? || loa.in?(LEVELS)
      end

      def valid_claims?(claims, session)
        super && requested_eid?(claims) && requested_level?(claims)
      end

      def valid_issuer?(claims)
        claims['iss'] == "https://#{domain}/auth/open"
      end

      def requested_eid?(claims)
        idps.empty? || claims['idp'].in?(idps)
      end

      def requested_level?(claims)
        return true if loa.blank?

        achieved = LEVELS.index(claims['acr'])
        achieved.present? && achieved >= LEVELS.index(loa)
      end
    end
  end
end
