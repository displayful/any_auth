# frozen_string_literal: true

module AnyAuth
  module ControllerHelpers
    private

    def redirect_to_provider(strategy, redirect_uri:, params: {})
      auth_request = strategy.request_phase(redirect_uri:)
      session[:any_auth] = {
        'provider' => strategy.provider,
        'request' => auth_request.session,
        'attributes' => strategy.attributes,
        'params' => params,
        'expires_at' => 10.minutes.from_now.to_i,
      }

      redirect_to auth_request.url, allow_other_host: true
    end

    def authenticate_with_provider(strategy)
      stored = stored_any_auth_request(strategy)
      session.delete(:any_auth)

      attributes = stored.fetch('attributes', {})
      strategy.assign_attributes(attributes.slice(*strategy.class.attribute_names))
      auth = strategy.callback_phase(callback_params, stored.fetch('request', {}))
      auth.with(params: stored.fetch('params', {}))
    end

    def any_auth_params(strategy)
      stored_any_auth_request(strategy).fetch('params', {})
    end

    def callback_params
      request.query_parameters.merge(request.request_parameters)
    end

    def stored_any_auth_request(strategy)
      stored = session[:any_auth]
      return {} unless stored && stored['provider'] == strategy.provider
      return {} unless Time.at(stored['expires_at']).future?

      stored
    end
  end
end
