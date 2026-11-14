# frozen_string_literal: true

module AnyAuth
  module ControllerHelpers
    private

    def redirect_to_provider(strategy, redirect_uri:, params: {})
      auth_request = strategy.request_phase(redirect_uri:)
      session[:any_auth] = {
        provider: strategy.provider,
        request: auth_request.session,
        attributes: strategy.attributes,
        params:,
        expires_at: 10.minutes.from_now.to_i,
      }

      redirect_to auth_request.url, allow_other_host: true
    end

    def authenticate_with_provider(strategy)
      stored = stored_any_auth_request(strategy)
      session.delete(:any_auth)
      strategy.assign_attributes(stored[:attributes].slice(*strategy.class.attribute_names))

      auth = strategy.callback_phase(request.query_parameters, stored[:request])
      auth.with(params: stored[:params])
    end

    def any_auth_params(strategy)
      stored_any_auth_request(strategy)[:params]
    end

    def stored_any_auth_request(strategy)
      stored = session.fetch(:any_auth, {}).with_indifferent_access
      expires_at = Time.at(stored[:expires_at].to_i)
      return stored if stored[:provider] == strategy.provider && expires_at.future?

      { request: {}, attributes: {}, params: {} }.with_indifferent_access
    end
  end
end
