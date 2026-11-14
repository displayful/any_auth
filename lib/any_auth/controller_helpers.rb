module AnyAuth
  module ControllerHelpers
    private

    def redirect_to_provider(strategy, redirect_uri:, as: strategy.provider, **extra)
      auth_request = strategy.request_phase(redirect_uri:)
      store_auth_request(as, auth_request, **extra)

      redirect_to auth_request.url, allow_other_host: true
    end

    def authenticate_with_provider(strategy, as: strategy.provider)
      strategy.callback_phase(request.query_parameters, take_auth_request(as)&.fetch('request'))
    end

    def store_auth_request(name, auth_request, **extra)
      cookies.encrypted["any_auth.#{name}"] = {
        value: extra.merge(request: auth_request.session).to_json,
        expires: 10.minutes,
        httponly: true,
        same_site: :lax,
        secure: request.ssl?,
      }
    end

    def take_auth_request(name)
      stored = cookies.encrypted["any_auth.#{name}"]
      cookies.delete("any_auth.#{name}")

      JSON.parse(stored) if stored
    end
  end
end
