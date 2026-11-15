# frozen_string_literal: true

begin
  gem 'ruby-saml', '>= 1.18.1'
  require 'onelogin/ruby-saml'
rescue LoadError => e
  raise LoadError, "AnyAuth::Strategies::Saml needs ruby-saml 1.18.1 or later: #{e.message}"
end

module AnyAuth
  module Strategies
    class Saml < Base
      attr_accessor :idp_sso_service_url, :idp_cert, :idp_entity_id, :sp_entity_id,
        :assertion_consumer_service_url, :name_identifier_format

      def request_phase(redirect_uri:)
        authn_request = OneLogin::RubySaml::Authrequest.new
        url = authn_request.create(settings(redirect_uri))
        session = { 'redirect_uri' => redirect_uri, 'request_id' => authn_request.request_id }

        Request.new(url:, session:)
      end

      def callback_phase(params, session)
        raise InvalidCallback, 'Missing SAMLResponse' if params['SAMLResponse'].blank?

        response = OneLogin::RubySaml::Response.new(
          params['SAMLResponse'],
          settings: settings(session['redirect_uri']),
          matches_request_id: session['request_id'],
          allowed_clock_drift: 5.seconds,
        )
        raise Unauthorized, 'Invalid SAML response' unless response.is_valid?

        Auth.new(
          provider:,
          uid: "#{idp_entity_id}:#{response.name_id}",
          info: info_from(response),
          credentials: {},
          raw: response.attributes.all.to_h,
        )
      end

      def metadata
        settings = service_provider
        require_present(settings)

        OneLogin::RubySaml::Metadata.new.generate(OneLogin::RubySaml::Settings.new(settings))
      end

      private

      def settings(redirect_uri = nil)
        settings = identity_provider.merge(service_provider(redirect_uri))
        require_present(settings)
        security = { strict_audience_validation: true, want_name_id: true }

        OneLogin::RubySaml::Settings.new(settings.merge(name_identifier_format:, security:), true)
      end

      def identity_provider
        { idp_sso_service_url:, idp_cert:, idp_entity_id: }
      end

      def service_provider(redirect_uri = nil)
        callback = assertion_consumer_service_url || redirect_uri

        { sp_entity_id:, assertion_consumer_service_url: callback }
      end

      def require_present(settings)
        missing = settings.select { |_name, value| value.blank? }.keys
        raise ArgumentError, "#{provider} needs #{missing.to_sentence}" if missing.any?
      end

      def info_from(response)
        attributes = response.attributes

        Info.new(name: attributes['name'], email: attributes['email'] || attributes['mail'])
      end
    end
  end
end
