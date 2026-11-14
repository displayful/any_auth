require 'any_auth'
require 'active_support/test_case'
require 'active_support/testing/time_helpers'
require 'minitest/autorun'
require 'rack/utils'
require 'webmock/minitest'

module ActiveSupport
  class TestCase
    CALLBACK_URL = 'https://tavle.test/callback'.freeze

    def stub_json(method, url, **body)
      stub_request(method, url).to_return(
        headers: { 'Content-Type' => 'application/json' },
        body: body.to_json
      )
    end

    def callback_params(**more)
      { 'code' => 'kode', 'state' => 's' }.merge(more.stringify_keys)
    end

    def stored_session(**more)
      { 'state' => 's', 'redirect_uri' => CALLBACK_URL }.merge(more.stringify_keys)
    end

    def id_token(claims)
      JWT.encode(claims, nil, 'none')
    end

    def query_of(url)
      Rack::Utils.parse_query(URI(url).query)
    end

    def challenge_for(verifier)
      Base64.urlsafe_encode64(::Digest::SHA256.digest(verifier), padding: false)
    end
  end
end
