# AnyAuth

OmniAuth's strategies, without the Rack.

A strategy is a plain Ruby object for one vendor. It knows the vendor's
endpoints, builds the address to send a person to, and turns what comes back
into credentials and, for sign-in, an identity. Your controller calls it. A
strategy never touches a request, a session or a database, so Rails' own
sign-in, CSRF protection and tenancy apply to every step.

```ruby
google = AnyAuth::Strategies::Google.new(client_id:, client_secret:)

request = google.request_phase(redirect_uri: "https://app.test/auth/google/callback")
request.url       # send the person here
request.session   # keep this until they come back

auth = google.callback_phase(params, session)
auth.uid          # "1184…"
auth.info.email   # "mette@acme.test"
```

## Why not OmniAuth

OmniAuth runs as middleware in front of your app. That is convenient until the
sign-in needs something only your app knows: who is signed in, which tenant
this is, which client secret that tenant uses, or what to do when it fails.
Then you carry that knowledge into the middleware through setup procs, `env`
keys and a failure endpoint.

AnyAuth keeps the part of OmniAuth that is worth keeping, one class per vendor
with the same named phases, and hands the flow back to your controllers.

| With OmniAuth | With AnyAuth |
| --- | --- |
| `provider :google_oauth2, id, secret` in an initializer | `config.provider :google, client_id:, client_secret:`, with anything overridden when you build one |
| The middleware owns `/auth/:provider` and its callback | Two ordinary routes and actions of your own |
| `request.env["omniauth.auth"]` | The return value of `callback_phase` |
| `/auth/failure` and `OmniAuth.config.on_failure` | `rescue_from AnyAuth::Error` |
| `omniauth-rails_csrf_protection` | Nothing: the request phase is your own `POST` action |
| A `setup` proc for per-request options | Build the strategy with what you know |
| `OmniAuth.config.test_mode` and `mock_auth` | Canned HTTP answers through your real controllers |
| A gem per vendor | A class per vendor, about fifteen lines |

## Signing in with Google, start to finish

```ruby
# Gemfile
gem "any_auth", github: "displayful/any_auth"

# config/routes.rb
constraints provider: /google|microsoft/ do
  post "auth/:provider",          to: "auth#create",   as: :auth
  get  "auth/:provider/callback", to: "auth#callback", as: :auth_callback
end
```

```ruby
# config/initializers/any_auth.rb
AnyAuth.configure do |config|
  config.provider :google,    client_id: ENV["GOOGLE_CLIENT_ID"],    client_secret: ENV["GOOGLE_CLIENT_SECRET"]
  config.provider :microsoft, client_id: ENV["MICROSOFT_CLIENT_ID"], client_secret: ENV["MICROSOFT_CLIENT_SECRET"]
end
```

```ruby
class AuthController < ApplicationController
  include AnyAuth::ControllerHelpers

  rescue_from AnyAuth::Error do
    redirect_to sign_in_path, alert: "That sign-in did not work. Try again."
  end

  def create
    redirect_to_provider strategy, redirect_uri: auth_callback_url(params[:provider])
  end

  def callback
    auth = authenticate_with_provider(strategy)
    user = User.find_by(provider: auth.provider, uid: auth.uid)

    user ? sign_in(user) : redirect_to(sign_up_path, alert: "No account for #{auth.info.email}.")
  end

  private

  def strategy
    AnyAuth.strategy(params[:provider])
  end
end
```

That is the whole integration. `redirect_to_provider` keeps the request in an
encrypted, HTTP-only cookie for ten minutes and sends the person off;
`authenticate_with_provider` reads it, removes it and answers the `auth`. Rails
expires the cookie, so there is nothing to clean up, and no session is needed.
The helpers need `cookies`, so an `ActionController::API` controller must
include `ActionController::Cookies`, and the ten minutes are enforced by Rails
only with `config.action_dispatch.use_cookies_with_metadata` on, as it is by
default since Rails 6.
The route constraint names the providers people may sign in with: the registry
can also hold providers you only connect APIs through, and those must not get a
sign-in address.

Each provider's request is kept under that provider's name, so a callback for
one can never use a request that left for another. Pass `as:` to both helpers
only if one provider needs two sign-ins under way at once.

Underneath are `store_auth_request(name, request, **extra)` and
`take_auth_request(name)`, for a flow that has to read what it stored before
it can build the strategy.

## One place for providers

`config.provider` names a provider and holds its defaults. `AnyAuth.strategy`
builds one, and whatever you pass then wins over the entry.

```ruby
AnyAuth.configure do |config|
  config.provider :google, client_id: -> { ENV["GOOGLE_CLIENT_ID"] }, client_secret: -> { ENV["GOOGLE_CLIENT_SECRET"] }

  # the same client, used for something else
  config.provider :google_drive, from: :google, scope: "https://www.googleapis.com/auth/drive.file"

  # the same code, with a client of its own
  config.provider :google_workspace, strategy: :google, client_id: "…", client_secret: "…"

  # only the kind; the client comes per tenant
  config.provider :shopify, scope: "read_orders"
end

AnyAuth.strategy(:google_drive)
AnyAuth.strategy(:shopify, client_id: tenant.client_id, client_secret: tenant.client_secret, shop: tenant.shop)
AnyAuth.providers   # => ["google", "google_drive", "google_workspace", "shopify"]
```

A value may be a callable, asked each time a strategy is built.
`auth.provider` answers the entry's name, so two uses of one vendor never get
mixed up.

Each strategy declares which options are sent to the vendor when the person
leaves: `scope` for every OAuth strategy; `access_type`, `prompt`, `hd` and
`login_hint` for Google; `prompt`, `login_hint` and `domain_hint` for
Microsoft. An option a strategy does not know is an
`ActiveModel::UnknownAttributeError`, so a misspelling fails where you wrote
it. To declare one in a strategy of your own, write `authorize_option :audience`.

Key a person on `auth.provider` and `auth.uid`, never on the email. Link to an
existing account by email only when `auth.info.email_verified` is true: it
means the vendor vouches that the person owns the address, which is stricter
than the vendor's own `email_verified` claim.

## Connecting an API instead of signing in

The same two phases, with the scope you need. What you store is
`auth.credentials`.

```ruby
hubspot = AnyAuth::Strategies::Hubspot.new(client_id:, client_secret:)

request = hubspot.request_phase(redirect_uri:, scope: "crm.objects.deals.read")
auth    = hubspot.callback_phase(params, session)

auth.credentials
# => { "access_token" => "…", "refresh_token" => "…", "expires_at" => "2026-11-13T10:00:00Z" }
```

## Calling the vendor's API afterwards

AnyAuth is not an HTTP client for the vendor's API. It answers the two things
any client needs: credentials that work right now, and how this vendor wants
them presented.

```ruby
credentials = strategy.fresh(credentials)   # unchanged if still good; renewed if about to expire
save(credentials)

Faraday.get("https://api.hubapi.com/crm/v3/objects/deals", nil, strategy.authorization(credentials))
```

| Strategy | `authorization(credentials)` |
| --- | --- |
| OAuth 2 | `{ "Authorization" => "Bearer …" }` |
| `Shopify` | `{ "X-Shopify-Access-Token" => "…" }` |
| `Adversus` | `{ "Authorization" => "Basic …" }` |
| `Economic` | `{ "X-AppSecretToken" => "…", "X-AgreementGrantToken" => "…" }` |

`strategy.expired?(credentials)` says whether a refresh is due, for an app that
wants to lock or reload before it renews. A vendor that rotates its refresh
token, as Shopify does, must not be refreshed twice at once.

## Vendors that ask for something first

A strategy is an ActiveModel, and its attributes are the fields a person
types. Shopify needs the shop before it can build an address:

```ruby
shopify = AnyAuth.strategy(:shopify, shop: "mystore")
shopify.valid?   # false, with errors on :shop, for anything that is not a shop
shopify.shop     # "mystore.myshopify.com"
```

### Showing the form

It is a form for a model, like any other. Give it a `scope`, so the parameters
do not carry the strategy's class name:

```erb
<%= form_with model: @strategy, scope: :strategy, url: shops_path do |form| %>
  <%= form.label :shop %>
  <%= form.text_field :shop %>
  <%= tag.p @strategy.errors.full_messages_for(:shop).to_sentence %>
  <%= form.submit "Connect" %>
<% end %>
```

`strategy.class.attribute_names` lists the fields, and
`strategy.class.fields?` says whether there are any, for a page that draws
whichever vendor it is given. The gem does not know which fields are secret;
choose `password_field` for those in your own view.

### Fields, then a round trip

Validate, then leave. The fields have to come back with the person, because
the callback needs the same strategy: store them with the request, and build
the strategy from them again.

```ruby
class ShopsController < ApplicationController
  include AnyAuth::ControllerHelpers

  def new
    @strategy = AnyAuth.strategy(:shopify)
  end

  def create
    @strategy = AnyAuth.strategy(:shopify, **fields)

    if @strategy.valid?
      redirect_to_provider @strategy, redirect_uri: callback_shops_url, fields: @strategy.attributes
    else
      render :new, status: :unprocessable_content
    end
  end

  def callback
    stored  = take_auth_request(:shopify)
    shopify = AnyAuth.strategy(:shopify, **stored.to_h.fetch("fields", {}).symbolize_keys)
    auth    = shopify.callback_phase(request.query_parameters, stored&.fetch("request"))

    current_account.shops.create!(credentials: shopify.attributes.merge(auth.credentials))
  end

  private

  def fields
    params.expect(strategy: AnyAuth.strategy_class(:shopify).attribute_names).to_h.symbolize_keys
  end
end
```

What you store is the fields and the tokens together. Building the strategy
from that hash later gives you both `shopify.shop` and working credentials.

### Fields and no round trip

Some vendors have you paste a token or a login from their settings page.
Those strategies inherit from `Base`. Show the same form, check `valid?`, and
store `strategy.attributes`. To find out whether the vendor accepts what was
typed, call its API once with `strategy.authorization(strategy.attributes)`
before you save.

## What comes back

| | |
| --- | --- |
| `auth.provider` | the name the provider is configured under: `"google"`, `"shopify"` |
| `auth.credentials` | `access_token`, and `refresh_token` and `expires_at` when the vendor sends them |
| `auth.uid` | the person's stable id at the vendor; OpenID Connect strategies only |
| `auth.info` | `email` and `email_verified`; OpenID Connect strategies only |

## Errors

Everything raised is an `AnyAuth::Error`. Rescue that one class, or tell them
apart:

| Error | Means | Usually |
| --- | --- | --- |
| `InvalidCallback` | the callback is not ours: wrong state, no code, a bad signature | start again |
| `Declined` | the vendor sent `error=`; `code` is what it sent | show why |
| `Unauthorized` | the vendor refused the code swap, the refresh or the ID token | sign in again |
| `Unavailable` | the vendor could not be reached, or answered nonsense | retry later |
| `RateLimited` | an `Unavailable` that asks you to slow down | retry later |

## Strategies included

Each has its own page under [docs/strategies](docs/strategies): what to
configure, what the vendor needs, what comes back and what is unusual.

| Strategy | Kind | Notes |
| --- | --- | --- |
| [`Google`](docs/strategies/google.md) | OpenID Connect | links by email for Gmail and Workspace addresses |
| [`Microsoft`](docs/strategies/microsoft.md) | OpenID Connect | work, school and personal accounts; `uid` is tenant and object id |
| [`Hubspot`](docs/strategies/hubspot.md) | OAuth 2 | |
| [`Relatel`](docs/strategies/relatel.md) | OAuth 2 | the vendor echoes no state |
| [`Shopify`](docs/strategies/shopify.md) | OAuth 2 with a field | per-shop endpoints, signed callback, expiring tokens |
| [`Economic`](docs/strategies/economic.md), [`Adversus`](docs/strategies/adversus.md) | fields only | pasted tokens or a login |
| [`Developer`](docs/strategies/developer.md) | fields only | type an email and be that person; for development only |

Register `Developer` only where it is safe, for example
`config.provider :developer if Rails.env.development?`. It goes through the
same two phases as the others, coming straight back to your callback.

## Writing a strategy

A standard OAuth 2 vendor is its endpoints:

```ruby
module AnyAuth
  module Strategies
    class Pipedrive < OAuth
      def client_options
        { site: "https://oauth.pipedrive.com", authorize_url: "/oauth/authorize", token_url: "/oauth/token" }
      end
    end
  end
end
```

`client_options` takes the same keys as an OmniAuth OAuth 2 strategy, so
porting one starts with copying that hash.

When a vendor is unusual, override only the step that differs and call
`super`:

| Step | Override when | Example |
| --- | --- | --- |
| `verify(params, session)` | the callback needs more than its state | Shopify's signature and shop |
| `exchange(code, session)` | the code swap takes extra parameters | Shopify's `expiring: 1` |
| `identity(token, session)` | the answer says who signed in | `OpenIDConnect` |
| `state?(params, session)` | the vendor sends no state back | Relatel |

For a vendor people sign in with, inherit from `OpenIDConnect` and answer
`identity_from(claims)` with `{ uid:, info: }`. The audience, expiry and nonce
are checked before it is called; checking the issuer is that method's job,
since vendors name theirs differently.

## What it does not do

- **SAML, OAuth 1, or callbacks that arrive as a cross-site `POST`** (Sign in
  with Apple's `form_post`). The phases leave room for them; none is built.
- **Discovery or key sets.** Endpoints are written in the strategy. The ID
  token is read from the token endpoint over TLS and checked for audience,
  expiry, nonce and issuer; its signature is not verified, which OpenID Connect
  allows for that path only. A token that reaches you through the browser must
  not be trusted this way.
- **A profile.** `info` is an email and whether it is vouched for. Ask the
  vendor's API for anything more.
- **Your user model, your session or your routes.** Those stay yours.

If you need a vendor that has an OmniAuth gem and none of the above bothers
you, OmniAuth is less work. AnyAuth is for when the sign-in has to know what
your app knows.
