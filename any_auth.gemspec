# frozen_string_literal: true

require_relative 'lib/any_auth/version'

Gem::Specification.new do |spec|
  spec.name = 'any_auth'
  spec.version = AnyAuth::VERSION
  spec.summary = "OmniAuth's strategies without the Rack: a vendor's fields and sign-in round trip as plain objects."
  spec.authors = ['Displayful']
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4'
  spec.homepage = 'https://github.com/displayful/any_auth'
  spec.files = Dir['lib/**/*.rb', 'README.md', 'CHANGELOG.md', 'LICENSE']
  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'documentation_uri' => "#{spec.homepage}/tree/main/docs",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true',
  }

  spec.add_dependency 'activemodel', '>= 8.0'
  spec.add_dependency 'activesupport', '>= 8.0'
  spec.add_dependency 'base64'
  spec.add_dependency 'faraday', '>= 2.14.3'
  spec.add_dependency 'jwt', '>= 3.2', '< 4'
  spec.add_dependency 'oauth2', '~> 2.0', '>= 2.0.22'

  spec.add_development_dependency 'actionpack'
  spec.add_development_dependency 'cgi'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'oauth', '>= 1.1.6'
  spec.add_development_dependency 'rack'
  spec.add_development_dependency 'railties'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'ruby-saml', '>= 1.18.1'
  spec.add_development_dependency 'webmock'
end
