# frozen_string_literal: true

require 'test_helper'
require 'any_auth/strategies/saml'

module AnyAuth
  module Strategies
    class SamlTest < ActiveSupport::TestCase
      IDP_SSO_URL = 'https://idp.acme.test/sso'
      IDP_ENTITY_ID = 'https://idp.acme.test'
      SP_ENTITY_ID = 'https://tavle.test/saml'

      test 'leaving sends the person to the IdP with a request' do
        request = saml.request_phase(redirect_uri: CALLBACK_URL)

        assert request.url.start_with?("#{IDP_SSO_URL}?SAMLRequest=")
        assert_predicate request.session['request_id'], :present?
      end

      test 'a signed response names the person by NameID, with the email it carries' do
        auth = saml.callback_phase({ 'SAMLResponse' => signed_response }, {})

        assert_equal 'saml', auth.provider
        assert_equal 'mette@acme.test', auth.uid
        assert_equal 'mette@acme.test', auth.info.email
        assert_equal 'Mette Holm', auth.info.name
        assert_not auth.info.email_verified
        assert_equal ['Mette Holm'], auth.raw['name']
      end

      test 'a response signed by another key, or changed after signing, is refused' do
        assert_raises(Unauthorized) do
          saml.callback_phase({ 'SAMLResponse' => signed_response(key: OTHER_KEY) }, {})
        end

        changed = Base64.decode64(signed_response).sub('Mette Holm', 'Someone Else')

        assert_raises(Unauthorized) do
          saml.callback_phase({ 'SAMLResponse' => Base64.strict_encode64(changed) }, {})
        end
      end

      test 'an unsigned response is refused' do
        expires = 5.minutes.from_now.utc.iso8601
        unsigned = response_xml(audience: SP_ENTITY_ID, not_on_or_after: expires,
          in_response_to: nil)

        assert_raises(Unauthorized) do
          saml.callback_phase({ 'SAMLResponse' => Base64.strict_encode64(unsigned) }, {})
        end
      end

      test 'an expired response, or one for another service, is refused' do
        expired = signed_response(not_on_or_after: 1.minute.ago)
        elsewhere = signed_response(audience: 'https://elsewhere.test')

        assert_raises(Unauthorized) { saml.callback_phase({ 'SAMLResponse' => expired }, {}) }
        assert_raises(Unauthorized) { saml.callback_phase({ 'SAMLResponse' => elsewhere }, {}) }
      end

      test 'when the sign-in was kept, a response to another request is refused' do
        answer = { 'SAMLResponse' => signed_response(in_response_to: '_another') }

        assert_raises(Unauthorized) { saml.callback_phase(answer, { 'request_id' => '_ours' }) }
      end

      test 'a callback with no response is not a sign-in' do
        assert_raises(InvalidCallback) { saml.callback_phase({}, {}) }
      end

      test 'the metadata names where the IdP sends people back' do
        assert_includes saml.metadata, CALLBACK_URL
        assert_includes saml.metadata, SP_ENTITY_ID
      end

      private

      KEY = OpenSSL::PKey::RSA.generate(2048)
      OTHER_KEY = OpenSSL::PKey::RSA.generate(2048)
      CERTIFICATE = OpenSSL::X509::Certificate.new.tap do |certificate|
        certificate.version = 2
        certificate.serial = 1
        certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse('/CN=idp.acme.test')
        certificate.public_key = KEY.public_key
        certificate.not_before = 1.day.ago
        certificate.not_after = 1.year.from_now
        certificate.sign(KEY, OpenSSL::Digest.new('SHA256'))
      end

      def saml
        Saml.new(
          idp_sso_service_url: IDP_SSO_URL,
          idp_entity_id: IDP_ENTITY_ID,
          idp_cert: CERTIFICATE.to_pem,
          sp_entity_id: SP_ENTITY_ID,
          assertion_consumer_service_url: CALLBACK_URL,
        )
      end

      def signed_response(key: KEY, audience: SP_ENTITY_ID, not_on_or_after: 5.minutes.from_now,
                          in_response_to: nil)
        xml = response_xml(audience:, not_on_or_after: not_on_or_after.utc.iso8601, in_response_to:)
        document = XMLSecurity::Document.new(xml)
        document.sign_document(key, CERTIFICATE, XMLSecurity::Document::RSA_SHA256,
          XMLSecurity::Document::SHA256)

        Base64.strict_encode64(document.to_s)
      end

      def response_xml(audience:, not_on_or_after:, in_response_to:)
        now = Time.now.utc.iso8601
        replying = %( InResponseTo="#{in_response_to}") if in_response_to
        protocol = 'urn:oasis:names:tc:SAML:2.0:protocol'
        assertion = 'urn:oasis:names:tc:SAML:2.0:assertion'
        email_format = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'
        password = 'urn:oasis:names:tc:SAML:2.0:ac:classes:Password'

        <<~XML.squish
          <samlp:Response xmlns:samlp="#{protocol}" xmlns:saml="#{assertion}" ID="_r1" Version="2.0"
            IssueInstant="#{now}" Destination="#{CALLBACK_URL}"#{replying}>
            <saml:Issuer>#{IDP_ENTITY_ID}</saml:Issuer>
            <samlp:Status>
              <samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/>
            </samlp:Status>
            <saml:Assertion ID="_a1" Version="2.0" IssueInstant="#{now}">
              <saml:Issuer>#{IDP_ENTITY_ID}</saml:Issuer>
              <saml:Subject>
                <saml:NameID Format="#{email_format}">mette@acme.test</saml:NameID>
                <saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">
                  <saml:SubjectConfirmationData NotOnOrAfter="#{not_on_or_after}"
                    Recipient="#{CALLBACK_URL}"#{replying}/>
                </saml:SubjectConfirmation>
              </saml:Subject>
              <saml:Conditions NotBefore="#{1.minute.ago.utc.iso8601}"
                NotOnOrAfter="#{not_on_or_after}">
                <saml:AudienceRestriction>
                  <saml:Audience>#{audience}</saml:Audience>
                </saml:AudienceRestriction>
              </saml:Conditions>
              <saml:AuthnStatement AuthnInstant="#{now}" SessionIndex="_s1">
                <saml:AuthnContext>
                  <saml:AuthnContextClassRef>#{password}</saml:AuthnContextClassRef>
                </saml:AuthnContext>
              </saml:AuthnStatement>
              <saml:AttributeStatement>
                <saml:Attribute Name="email">
                  <saml:AttributeValue>mette@acme.test</saml:AttributeValue>
                </saml:Attribute>
                <saml:Attribute Name="name">
                  <saml:AttributeValue>Mette Holm</saml:AttributeValue>
                </saml:Attribute>
              </saml:AttributeStatement>
            </saml:Assertion>
          </samlp:Response>
        XML
      end
    end
  end
end
