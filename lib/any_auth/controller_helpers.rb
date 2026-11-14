module AnyAuth
  module ControllerHelpers
    private

    def redirect_to_provider(strategy, redirect_uri:, params: {})
      auth_request = strategy.request_phase(redirect_uri:)
      remember_sign_in(strategy, auth_request, params)

      redirect_to auth_request.url, allow_other_host: true
    end

    def authenticate_with_provider(strategy)
      remembered = recall_sign_in(strategy)
      session.delete(:any_auth)
      strategy.assign_attributes(remembered[:attributes].slice(*strategy.class.attribute_names))

      auth = strategy.callback_phase(request.query_parameters, remembered[:request])
      auth.with(params: remembered[:params])
    end

    def provider_params(strategy)
      recall_sign_in(strategy)[:params]
    end

    def remember_sign_in(strategy, auth_request, params)
      session[:any_auth] = {
        provider: strategy.provider,
        request: auth_request.session,
        attributes: strategy.attributes,
        params:,
        expires_at: 10.minutes.from_now.to_i,
      }
    end

    def recall_sign_in(strategy)
      remembered = session.fetch(:any_auth, {}).with_indifferent_access
      return remembered if remembered[:provider] == strategy.provider && Time.at(remembered[:expires_at].to_i).future?

      { request: {}, attributes: {}, params: {} }.with_indifferent_access
    end
  end
end
