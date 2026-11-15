# frozen_string_literal: true

module AnyAuth
  module ControllerHelpers
    private

    def redirect_to_provider(strategy, redirect_uri:, params: {})
      auth_request = strategy.request_phase(redirect_uri:)
      stored = {
        'provider' => strategy.provider,
        'request' => auth_request.session,
        'attributes' => strategy.attributes,
        'params' => params,
        'expires_at' => 10.minutes.from_now.to_i,
      }
      cookies.encrypted[any_auth_cookie_name] = {
        value: stored, expires: 10.minutes, httponly: true, **any_auth_cookie_options
      }

      redirect_to auth_request.url, allow_other_host: true
    end

    def authenticate_with_provider(strategy)
      stored = any_auth_cookie(strategy)
      cookies.delete(any_auth_cookie_name, **any_auth_cookie_options)

      attributes = stored.fetch('attributes', {})
      strategy.assign_attributes(attributes.slice(*strategy.class.attribute_names))
      auth = strategy.callback_phase(callback_params, stored.fetch('request', {}))
      auth.with(params: stored.fetch('params', {}))
    end

    def any_auth_params(strategy)
      any_auth_cookie(strategy).fetch('params', {})
    end

    def callback_params
      request.query_parameters.merge(request.request_parameters)
    end

    def any_auth_cookie(strategy)
      stored = cookies.encrypted[any_auth_cookie_name]
      return {} unless stored.is_a?(Hash) && stored['provider'] == strategy.provider
      return {} unless Time.at(stored['expires_at'].to_i).future?

      stored
    end

    def any_auth_cookie_name
      return '__Host-any_auth' if request.ssl?

      'any_auth'
    end

    def any_auth_cookie_options
      return { secure: true, same_site: :none } if request.ssl?

      { same_site: :lax }
    end
  end
end
