# AnyAuth

Sign in at a vendor from a Rails controller. One strategy class per vendor,
with the phases OmniAuth names, called from your own actions.

```ruby
class AuthController < ApplicationController
  include AnyAuth::ControllerHelpers

  def create
    redirect_to_provider AnyAuth.strategy(:google), redirect_uri: auth_callback_url
  end

  def callback
    auth = authenticate_with_provider(AnyAuth.strategy(:google))
    auth.uid          # "1184…"
    auth.info.email   # "mette@acme.test"
  end
end
```

Needs Ruby 3.4, Rails 8 and a session.

## Setup

```ruby
# Gemfile
gem "any_auth", github: "displayful/any_auth"

# config/initializers/any_auth.rb
AnyAuth.configure do |config|
  config.provider :google,    client_id: ENV["GOOGLE_CLIENT_ID"],    client_secret: ENV["GOOGLE_CLIENT_SECRET"]
  config.provider :microsoft, client_id: ENV["MICROSOFT_CLIENT_ID"], client_secret: ENV["MICROSOFT_CLIENT_SECRET"]
end

# config/routes.rb
constraints provider: /google|microsoft/ do
  post "auth/:provider",          to: "auth#create",   as: :auth
  get  "auth/:provider/callback", to: "auth#callback", as: :auth_callback
end
```

The constraint names the providers people may sign in with. Start the sign-in
with a `POST` that is not a Turbo submission (`data: { turbo: false }`).

## Controller helpers

| | |
| --- | --- |
| `redirect_to_provider(strategy, redirect_uri:, params: {})` | sends the person to the vendor |
| `authenticate_with_provider(strategy)` | checks the callback, swaps the code, returns the `auth` |
| `any_auth_params(strategy)` | the `params:` you passed, readable before the code is swapped |

The sign-in is kept in the session for ten minutes and used once. One sign-in
at a time: a second replaces the first.

```ruby
redirect_to_provider strategy, redirect_uri: callback_url, params: { return_to: "/boards" }

auth = authenticate_with_provider(strategy)
auth.params[:return_to]   # "/boards"
```

## What comes back

| | |
| --- | --- |
| `auth.provider` | the name the provider is configured under |
| `auth.uid` | who signed in, as the vendor identifies them |
| `auth.info` | `name`, `email`, `email_verified`, `image`; nil where the vendor does not say |
| `auth.credentials` | `access_token`, and `refresh_token` and `expires_at` when sent |
| `auth.raw` | what the vendor said, untouched |
| `auth.params` | what you passed as `params:` |

`uid` is the person, never the account they opened. A vendor with tenants
names the tenant in `raw`:

| Strategy | `uid` | In `raw` |
| --- | --- | --- |
| Google | `sub` | `hd`, the Workspace domain |
| Microsoft | `<tenant id>:<object id>` | `tid`, the tenant |
| HubSpot | the user's id | `hub_id`, `hub_domain` |
| Relatel | the employee's id | `company_id` |
| Shopify | the shop's domain | the granted scope |

Key a person on `provider` and `uid`. Link an existing account by email only
when `info.email_verified` is true: it means the vendor vouches for the
address, which is stricter than the vendor's own claim.

## Providers

`config.provider` names a provider and its defaults. What you pass to
`AnyAuth.strategy` wins.

```ruby
config.provider :google, client_id: -> { ENV["GOOGLE_CLIENT_ID"] }, client_secret: -> { ENV["GOOGLE_CLIENT_SECRET"] }
config.provider :google_drive, from: :google, scope: "https://www.googleapis.com/auth/drive.file"   # same client
config.provider :google_workspace, strategy: :google, client_id: "…", client_secret: "…"            # same code
config.provider :shopify, scope: "read_orders"                                                       # client per tenant

AnyAuth.strategy(:shopify, client_id: tenant.client_id, client_secret: tenant.client_secret)
AnyAuth.providers   # => ["google", "google_drive", "google_workspace", "shopify"]
```

- A callable value is asked each time a strategy is built.
- A `scope` you set replaces the default `email profile`.
- Options sent to the vendor are declared per strategy: `scope` everywhere;
  `access_type`, `prompt`, `hd`, `login_hint` for Google; `prompt`,
  `login_hint`, `domain_hint` for Microsoft. An unknown option raises
  `ActiveModel::UnknownAttributeError` when the strategy is built.

## Fields

A strategy is an ActiveModel. Its attributes are what a person types before
signing in, such as Shopify's shop.

```ruby
AnyAuth.strategy_class(:shopify).attribute_names   # => ["shop"]

strategy = AnyAuth.strategy(:shopify, params.expect(strategy: [:shop]))
strategy.valid?        # false with an error on :shop for anything that is not a shop
strategy.attributes    # => { "shop" => "mystore.myshopify.com" }
```

```erb
<%= form_with model: @strategy, scope: :strategy, url: shops_path do |form| %>
  <%= form.label :shop %>
  <%= form.text_field :shop %>
  <%= tag.p @strategy.errors.full_messages_for(:shop).to_sentence %>
  <%= form.submit "Connect" %>
<% end %>
```

```ruby
def create
  @strategy = AnyAuth.strategy(:shopify, params.expect(strategy: [:shop]))

  if @strategy.valid?
    redirect_to_provider @strategy, redirect_uri: callback_shops_url
  else
    render :new, status: :unprocessable_content
  end
end

def callback
  shopify = AnyAuth.strategy(:shopify)
  auth    = authenticate_with_provider(shopify)   # puts the shop back on the strategy

  current_account.shops.create!(credentials: shopify.attributes.merge(auth.credentials))
end
```

Permit `attribute_names` and nothing else; unpermitted parameters raise
`ActiveModel::ForbiddenAttributesError`. `Economic` and `Adversus` have fields
and no sign-in: check `valid?` and store `strategy.attributes`.

## Refreshing

```ruby
credentials = strategy.refresh(credentials)   # renewed if about to expire, otherwise unchanged
```

| | |
| --- | --- |
| `expired?(credentials)` | the access token runs out within two minutes |
| `refresh(credentials)` | renews when expired; returns the whole hash either way |
| `refresh!(credentials)` | asks the vendor now |

A vendor that rotates its refresh token, as Shopify does, must not be
refreshed twice at once. Sending the token to the vendor's API is your
client's job; each [strategy page](docs/strategies) says how the vendor wants
it.

## Errors

| Error | Means |
| --- | --- |
| `InvalidCallback` | the callback is not ours: wrong state, no code, a bad signature, nothing under way |
| `Declined` | the vendor sent `error=`; `code` holds it |
| `Unauthorized` | the vendor refused the code, the refresh or the ID token |
| `Unavailable` | a timeout, a server error, an answer we cannot read |
| `RateLimited` | an `Unavailable` asking us to slow down |

All are `AnyAuth::Error`. Mistakes in setup are ordinary Ruby errors: an
unconfigured provider is a `KeyError`.

## Strategies

| Strategy | Kind | |
| --- | --- | --- |
| [`Google`](docs/strategies/google.md) | OpenID Connect | |
| [`Microsoft`](docs/strategies/microsoft.md) | OpenID Connect | work, school and personal accounts |
| [`Apple`](docs/strategies/apple.md) | OpenID Connect | signed client secret; the callback is a `POST` you send on |
| [`Hubspot`](docs/strategies/hubspot.md) | OAuth 2 | one more request, to name the user |
| [`Relatel`](docs/strategies/relatel.md) | OAuth 2 | one more request, to name the employee |
| [`Shopify`](docs/strategies/shopify.md) | OAuth 2 with a field | per-shop endpoints, signed callback |
| [`Economic`](docs/strategies/economic.md), [`Adversus`](docs/strategies/adversus.md) | fields only | |
| [`Developer`](docs/strategies/developer.md) | a field | sign in as anyone; development only, loaded on request |

A new OAuth 2 vendor is its endpoints:

```ruby
class Pipedrive < AnyAuth::Strategies::OAuth
  def client_options
    { site: "https://oauth.pipedrive.com", authorize_url: "/oauth/authorize", token_url: "/oauth/token" }
  end
end

config.provider :pipedrive, strategy: Pipedrive, client_id: "…", client_secret: "…"
```

Override only the step that differs, calling `super`:

| Step | For | Example |
| --- | --- | --- |
| `verify(params, session)` | a callback that needs more than its state | Shopify's signature |
| `exchange(code, session)` | extra parameters on the code swap | Shopify's `expiring: 1` |
| `identity(token, session)` | saying who signed in | `OpenIDConnect` |

PKCE is a switch on every OAuth strategy: off for plain OAuth 2, on for
`OpenIDConnect`. Turn it on for a vendor that accepts a `code_challenge`,
in the class (`self.pkce = true`) or where it is configured (`pkce: true`).

For sign-in, inherit from `OpenIDConnect` and answer `identity_from(claims)`
with `{ uid:, info: }`, checking the issuer there.

## Coming from OmniAuth

| OmniAuth | AnyAuth |
| --- | --- |
| `provider :google_oauth2, id, secret` | `config.provider :google, client_id:, client_secret:` |
| `/auth/:provider` and its callback | two routes and actions of your own |
| `request.env["omniauth.auth"]` | the return value of `authenticate_with_provider` |
| `omniauth.params`, `omniauth.origin` | `params:`, read back as `auth.params` |
| `/auth/failure` | `rescue_from AnyAuth::Error` |
| a `setup` proc | attributes passed to `AnyAuth.strategy` |
| `extra.raw_info` | `auth.raw` |

- Keep your provider names: `config.provider :google_oauth2, strategy: :google`.
- Compare `uid`s before switching. Google's is the same `sub`; Microsoft's is
  `<tenant id>:<object id>`.
- `auth` is an object: `auth.uid`, not `auth["uid"]`. `credentials` has
  `access_token` where OmniAuth has `token`, and `expires_at` as ISO 8601 text.

## Testing

Stub the vendor's HTTP answers and drive your controllers:

```ruby
post auth_path(:google)
sent = Rack::Utils.parse_query(URI(response.location).query)

claims = { sub: "g-1", email: "mette@gmail.com", email_verified: true, iss: "https://accounts.google.com",
           aud: "your-client-id", exp: 1.hour.from_now.to_i, nonce: sent["nonce"] }
stub_request(:post, "https://oauth2.googleapis.com/token").to_return(
  headers: { "Content-Type" => "application/json" },
  body: { access_token: "token", id_token: JWT.encode(claims, nil, "none") }.to_json
)

get auth_callback_path(:google, code: "code", state: sent["state"])
```

## Without the helpers

```ruby
request = strategy.request_phase(redirect_uri: "https://app.test/callback")
request.url       # where to send the person
request.session   # keep until they come back

auth = strategy.callback_phase(query, kept)   # string-keyed hashes
```

Keeping `request.session` safe, for a limited time and one use, is then yours
to do, as is giving the strategy its fields again in the callback.

## Limits

- No SAML or OAuth 1. A callback that arrives as a cross-site `POST` is sent
  on to a `GET` by your app, as [Apple's](docs/strategies/apple.md) is.
- Endpoints are written in the strategy; there is no discovery.
- The ID token is read from the token endpoint over TLS and checked for
  audience, expiry, nonce and issuer. Its signature is not verified, which
  OpenID Connect allows for that path only.
- `info` is a name, an email, whether it is vouched for, and a picture.
