# frozen_string_literal: true

begin
  require 'onelogin/ruby-saml'
rescue LoadError
  raise LoadError, 'AnyAuth::Strategies::Saml needs the ruby-saml gem, 1.18.1 or later. ' \
                   'Add it to your Gemfile.'
end

if Gem::Version.new(OneLogin::RubySaml::VERSION) < Gem::Version.new('1.18.1')
  raise LoadError, "AnyAuth::Strategies::Saml needs ruby-saml 1.18.1 or later; " \
                   "#{OneLogin::RubySaml::VERSION} has known signature bypasses."
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

        Auth.new(provider:, uid: response.name_id, info: info_from(response), credentials: {},
          raw: response.attributes.all.to_h)
      end

      def metadata
        OneLogin::RubySaml::Metadata.new.generate(settings)
      end

      private

      def settings(redirect_uri = nil)
        OneLogin::RubySaml::Settings.new(
          idp_sso_service_url:,
          idp_cert:,
          idp_entity_id:,
          sp_entity_id:,
          name_identifier_format:,
          assertion_consumer_service_url: assertion_consumer_service_url || redirect_uri,
        )
      end

      def info_from(response)
        attributes = response.attributes

        Info.new(name: attributes['name'], email: attributes['email'] || attributes['mail'])
      end
    end
  end
end
