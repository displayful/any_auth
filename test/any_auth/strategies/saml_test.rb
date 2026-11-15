# frozen_string_literal: true

require 'test_helper'
require 'any_auth/strategies/saml'

module AnyAuth
  module Strategies
    class SamlTest < ActiveSupport::TestCase
      IDP_SSO_URL = 'https://idp.acme.test/sso'
      IDP_ENTITY_ID = 'https://idp.acme.test'
      SP_ENTITY_ID = 'https://tavle.test/saml'
      EMAIL_FORMAT = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'

      test 'leaving sends the person to the IdP with a request' do
        request = saml.request_phase(redirect_uri: CALLBACK_URL)

        assert request.url.start_with?("#{IDP_SSO_URL}?SAMLRequest=")
        assert_predicate request.session['request_id'], :present?
      end

      test 'a signed response names the person by IdP and NameID, with the email it carries' do
        auth = post_back(signed_response)

        assert_equal 'saml', auth.provider
        assert_equal 'https://idp.acme.test:mette@acme.test', auth.uid
        assert_equal 'mette@acme.test', auth.info.email
        assert_equal 'Mette Holm', auth.info.name
        assert_not auth.info.email_verified
        assert_equal ['Mette Holm'], auth.raw['name']
      end

      test 'a response signed by another key, or changed after signing, is refused' do
        assert_raises(InvalidCallback) do
          post_back(signed_response(key: OTHER_KEY))
        end

        changed = Base64.decode64(signed_response).sub('Mette Holm', 'Someone Else')

        assert_raises(InvalidCallback) do
          post_back(Base64.strict_encode64(changed))
        end
      end

      test 'an unsigned response is refused' do
        expires = 5.minutes.from_now.utc.iso8601
        unsigned = response_xml(audience: SP_ENTITY_ID, not_on_or_after: expires,
          in_response_to: nil)

        assert_raises(InvalidCallback) do
          post_back(Base64.strict_encode64(unsigned))
        end
      end

      test 'a response naming no audience, or no person, is refused' do
        nobody_in_particular = signed_response(audience: nil)
        nobody = signed_response(name_id: nil)

        assert_raises(InvalidCallback) do
          post_back(nobody_in_particular)
        end
        assert_raises(InvalidCallback) { post_back(nobody) }
      end

      test 'a strategy missing a setting it checks against is an error, not a sign-in' do
        incomplete = Saml.new(idp_sso_service_url: IDP_SSO_URL, idp_cert: CERTIFICATE.to_pem,
          assertion_consumer_service_url: CALLBACK_URL)

        error = assert_raises(ArgumentError) do
          incomplete.callback_phase({ 'SAMLResponse' => signed_response }, KEPT)
        end

        assert_includes error.message, 'idp_entity_id'
        assert_includes error.message, 'sp_entity_id'
      end

      test 'an expired response, or one for another service, is refused' do
        expired = signed_response(not_on_or_after: 1.minute.ago)
        elsewhere = signed_response(audience: 'https://elsewhere.test')

        assert_raises(InvalidCallback) { post_back(expired) }
        assert_raises(InvalidCallback) { post_back(elsewhere) }
      end

      test 'a response to another request is refused' do
        assert_raises(InvalidCallback) { post_back(signed_response(in_response_to: '_another')) }
      end

      test 'a response nobody asked for is refused, unless the IdP may start sign-ins' do
        unasked = { 'SAMLResponse' => signed_response(in_response_to: nil) }
        idp_initiated = saml
        idp_initiated.allow_idp_initiated = true

        assert_raises(InvalidCallback) { saml.callback_phase(unasked, {}) }
        assert_equal 'saml', idp_initiated.callback_phase(unasked, {}).provider
      end

      test 'a switch for IdP-initiated sign-ins read as text is still off when it says so' do
        unasked = { 'SAMLResponse' => signed_response(in_response_to: nil) }
        off = saml
        off.allow_idp_initiated = 'false'

        assert_raises(InvalidCallback) { off.callback_phase(unasked, {}) }
      end

      test 'an assertion that never expires is refused' do
        xml = response_xml(audience: SP_ENTITY_ID, not_on_or_after: 5.minutes.from_now.iso8601,
          in_response_to: '_ours')
        never = xml.sub(/(<saml:Conditions NotBefore="[^"]+") NotOnOrAfter="[^"]+"/, '\\1')

        assert_raises(InvalidCallback) { post_back(sign(never)) }
      end

      test 'without a cache that keeps what it is given, replays cannot be refused' do
        uncached = saml
        uncached.cache = ActiveSupport::Cache::NullStore.new

        answer = { 'SAMLResponse' => signed_response }

        assert_raises(ArgumentError) { uncached.callback_phase(answer, KEPT) }
      end

      test 'a response used once is refused the second time' do
        once = saml
        response = signed_response

        once.callback_phase({ 'SAMLResponse' => response }, KEPT)

        assert_raises(InvalidCallback) { once.callback_phase({ 'SAMLResponse' => response }, KEPT) }
      end

      test 'a person the IdP could not authenticate is AccessDenied, with its status' do
        failed = signed_response(status: %w[Responder AuthnFailed])

        refused = assert_raises(AccessDenied) { post_back(failed) }

        assert_includes refused.code, 'AuthnFailed'
      end

      test 'a failure status, which an IdP need not sign, carries none of its own text' do
        forged = response_xml(audience: SP_ENTITY_ID, not_on_or_after: 5.minutes.from_now.iso8601,
          in_response_to: '_ours', status: %w[Requester])
        message = '<samlp:StatusMessage>forged</samlp:StatusMessage>'
        forged = forged.sub('</samlp:Status>', "#{message}</samlp:Status>")

        refused = assert_raises(AccessDenied) { post_back(Base64.strict_encode64(forged)) }

        assert_nil refused.description
        assert_not_includes refused.message, 'forged'
      end

      test 'a callback with no response is not a sign-in' do
        assert_raises(InvalidCallback) { saml.callback_phase({}, KEPT) }
      end

      test 'the metadata names where the IdP sends people back, before the IdP is set up' do
        before_the_idp = Saml.new(sp_entity_id: SP_ENTITY_ID,
          assertion_consumer_service_url: CALLBACK_URL)

        assert_includes before_the_idp.metadata, CALLBACK_URL
        assert_includes before_the_idp.metadata, SP_ENTITY_ID
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

      KEPT = { 'request_id' => '_ours' }.freeze

      def post_back(response)
        saml.callback_phase({ 'SAMLResponse' => response }, KEPT)
      end

      def saml
        Saml.new(
          idp_sso_service_url: IDP_SSO_URL,
          idp_entity_id: IDP_ENTITY_ID,
          idp_cert: CERTIFICATE.to_pem,
          sp_entity_id: SP_ENTITY_ID,
          assertion_consumer_service_url: CALLBACK_URL,
          cache: ActiveSupport::Cache::MemoryStore.new,
        )
      end

      def signed_response(key: KEY, audience: SP_ENTITY_ID, name_id: 'mette@acme.test',
                          not_on_or_after: 5.minutes.from_now, in_response_to: '_ours',
                          status: %w[Success])
        xml = response_xml(audience:, name_id:, not_on_or_after: not_on_or_after.utc.iso8601,
          in_response_to:, status:)

        sign(xml, key:)
      end

      def sign(xml, key: KEY)
        document = XMLSecurity::Document.new(xml)
        document.sign_document(key, CERTIFICATE, XMLSecurity::Document::RSA_SHA256,
          XMLSecurity::Document::SHA256)

        Base64.strict_encode64(document.to_s)
      end

      def status_code(names)
        names.reverse.reduce('') do |nested, name|
          value = "urn:oasis:names:tc:SAML:2.0:status:#{name}"

          %(<samlp:StatusCode Value="#{value}">#{nested}</samlp:StatusCode>)
        end
      end

      def response_xml(audience:, not_on_or_after:, in_response_to:, name_id: 'mette@acme.test',
                       status: %w[Success])
        now = Time.now.utc.iso8601
        replying = %( InResponseTo="#{in_response_to}") if in_response_to
        naming = %(<saml:NameID Format="#{EMAIL_FORMAT}">#{name_id}</saml:NameID>) if name_id
        audience = "<saml:Audience>#{audience}</saml:Audience>" if audience
        restriction = "<saml:AudienceRestriction>#{audience}</saml:AudienceRestriction>" if audience
        protocol = 'urn:oasis:names:tc:SAML:2.0:protocol'
        assertion = 'urn:oasis:names:tc:SAML:2.0:assertion'
        password = 'urn:oasis:names:tc:SAML:2.0:ac:classes:Password'

        <<~XML.squish
          <samlp:Response xmlns:samlp="#{protocol}" xmlns:saml="#{assertion}" ID="_r1" Version="2.0"
            IssueInstant="#{now}" Destination="#{CALLBACK_URL}"#{replying}>
            <saml:Issuer>#{IDP_ENTITY_ID}</saml:Issuer>
            <samlp:Status>#{status_code(status)}</samlp:Status>
            <saml:Assertion ID="_a1" Version="2.0" IssueInstant="#{now}">
              <saml:Issuer>#{IDP_ENTITY_ID}</saml:Issuer>
              <saml:Subject>
                #{naming}
                <saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">
                  <saml:SubjectConfirmationData NotOnOrAfter="#{not_on_or_after}"
                    Recipient="#{CALLBACK_URL}"#{replying}/>
                </saml:SubjectConfirmation>
              </saml:Subject>
              <saml:Conditions NotBefore="#{1.minute.ago.utc.iso8601}"
                NotOnOrAfter="#{not_on_or_after}">
                #{restriction}
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
