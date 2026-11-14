require 'any_auth'
require 'active_support/test_case'
require 'active_support/testing/time_helpers'
require 'minitest/autorun'
require 'rack/utils'
require 'webmock/minitest'

module ActiveSupport
  class TestCase
    def stub_json(method, url, **body)
      stub_request(method, url).to_return(headers: { 'Content-Type' => 'application/json' }, body: body.to_json)
    end

    def id_token(claims)
      JWT.encode(claims, nil, 'none')
    end

    def query_of(url)
      Rack::Utils.parse_query(URI(url).query)
    end
  end
end
