# frozen_string_literal: true

begin
  gem 'oauth', '>= 1.1'
  require 'oauth'
rescue LoadError => e
  raise LoadError, "AnyAuth::Strategies::OAuth1 needs the oauth gem: #{e.message}"
end

unless CGI.respond_to?(:parse)
  raise LoadError, 'AnyAuth::Strategies::OAuth1 needs the cgi gem on Ruby 4.0, where CGI.parse ' \
                   'left Ruby itself and the oauth gem still calls it. ' \
                   'Add gem "cgi" to your Gemfile.'
end

module AnyAuth
  module Strategies
    class OAuth1 < Base
      attr_accessor :consumer_key, :consumer_secret

      def request_phase(redirect_uri:)
        request_token = with_error_handling do
          consumer.get_request_token(oauth_callback: redirect_uri)
        end
        session = {
          'request_token' => request_token.token,
          'request_token_secret' => request_token.secret,
        }

        Request.new(url: request_token.authorize_url, session:)
      end

      def callback_phase(params, session)
        verify(params, session)
        access_token = fetch_access_token(params['oauth_verifier'], session)
        credentials = { 'token' => access_token.token, 'secret' => access_token.secret }

        Auth.new(provider:, credentials:, **identity(access_token, session))
      end

      private

      def verify(params, session)
        request_token = session['request_token']

        raise InvalidCallback, 'No sign-in in progress' if request_token.blank?
        raise Declined, 'denied' if secure_compare(request_token, params['denied'])
        raise InvalidCallback, 'Invalid oauth_token' unless valid_token?(request_token, params)
        raise InvalidCallback, 'Missing oauth_verifier' if params['oauth_verifier'].blank?
      end

      def valid_token?(request_token, params)
        secure_compare(request_token, params['oauth_token'])
      end

      def fetch_access_token(verifier, session)
        request_token = ::OAuth::RequestToken.new(consumer, session['request_token'],
          session['request_token_secret'])

        with_error_handling { request_token.get_access_token(oauth_verifier: verifier) }
      end

      def identity(_access_token, _session)
        {}
      end

      def consumer
        ::OAuth::Consumer.new(consumer_key, consumer_secret, client_options)
      end

      def get(access_token, path)
        response = with_error_handling { access_token.get(path) }
        unless response.is_a?(Net::HTTPSuccess)
          raise error_class_for(response.code.to_i), "#{provider} returned #{response.code}"
        end

        body = JSON.parse(response.body)
        raise Unavailable, "#{provider} returned an unreadable response" unless body.is_a?(Hash)

        body
      rescue JSON::ParserError
        raise Unavailable, "#{provider} returned an unreadable response", cause: nil
      end

      def with_error_handling
        yield
      rescue ::OAuth::Unauthorized => e
        status = e.request&.code.to_i
        raise error_class_for(status), "#{provider} returned #{status}", cause: nil
      rescue Net::HTTPExceptions, Timeout::Error, SystemCallError, SocketError,
             OpenSSL::SSL::SSLError => e
        raise Unavailable, "#{provider} request failed (#{e.class.name.demodulize})", cause: nil
      end
    end
  end
end
