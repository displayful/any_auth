module AnyAuth
  module ControllerHelpers
    extend ActiveSupport::Concern

    private

    def redirect_to_provider(strategy, redirect_uri:, params: {})
      auth_request = strategy.request_phase(redirect_uri:)
      session[provider_session_key(strategy)] = {
        'request' => auth_request.session,
        'attributes' => strategy.attributes,
        'params' => params.to_h.deep_stringify_keys,
        'expires_at' => 10.minutes.from_now.to_i,
      }

      redirect_to auth_request.url, allow_other_host: true
    end

    def authenticate_with_provider(strategy)
      kept = kept_for(strategy)
      session.delete(provider_session_key(strategy))
      strategy.assign_attributes(kept['attributes'].to_h)

      strategy.callback_phase(request.query_parameters, kept['request']).with(params: kept['params'].to_h)
    end

    def provider_params(strategy)
      kept_for(strategy)['params'].to_h
    end

    def kept_for(strategy)
      kept = session[provider_session_key(strategy)].to_h.deep_stringify_keys

      kept['expires_at'].to_i > Time.now.to_i ? kept : {}
    end

    def provider_session_key(strategy)
      "any_auth.#{strategy.provider}"
    end
  end
end
