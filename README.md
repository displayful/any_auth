# AnyAuth

Sign people in with Google, Microsoft, Apple and others, and connect your app
to vendors' APIs, from your own Rails controllers. One strategy class per
vendor, with the request and callback phases OmniAuth names, and no Rack
middleware.

Needs Ruby 3.4, Rails 8 and a session.

- [Sign in with Google and Microsoft](#sign-in-with-google-and-microsoft)
- [Connect to a vendor's API](#connect-to-a-vendors-api)
- [Reference](#reference)
- [Writing a strategy](#writing-a-strategy)
- [Coming from OmniAuth](#coming-from-omniauth)
- [Testing](#testing)
- [Developer docs](docs/README.md): adding a strategy, how a sign-in works, each strategy

## Sign in with Google and Microsoft

### 1. Install

```ruby
# Gemfile
gem "any_auth", github: "displayful/any_auth"
```

### 2. Register the providers

Create an OAuth client at each vendor and add your callback address as a
redirect URI: `https://example.com/auth/google/callback`. Each
[strategy page](docs/strategies) says where.

```ruby
# config/initializers/any_auth.rb
AnyAuth.configure do |config|
  config.provider :google,
    client_id: ENV["GOOGLE_CLIENT_ID"], client_secret: ENV["GOOGLE_CLIENT_SECRET"]
  config.provider :microsoft,
    client_id: ENV["MICROSOFT_CLIENT_ID"], client_secret: ENV["MICROSOFT_CLIENT_SECRET"]
end
```

### 3. Add two routes

```ruby
# config/routes.rb
post "auth/:provider",          to: "auth#create",   as: :auth
get  "auth/:provider/callback", to: "auth#callback", as: :auth_callback
```

### 4. Write the controller

```ruby
class AuthController < ApplicationController
  include AnyAuth::ControllerHelpers

  SIGN_IN = %w[google microsoft]

  before_action :set_strategy
  rescue_from AnyAuth::Error, with: :refused

  def create
    redirect_to_provider @strategy, redirect_uri: auth_callback_url(params[:provider])
  end

  def callback
    auth = authenticate_with_provider(@strategy)
    user = User.from_any_auth(auth)
    return refused unless user

    reset_session
    session[:user_id] = user.id
    redirect_to root_path
  end

  private

  def set_strategy
    return head :not_found unless params[:provider].in?(SIGN_IN)

    @strategy = AnyAuth.strategy(params[:provider])
  end

  def refused
    redirect_to sign_in_path, alert: "We could not sign you in. Try another way."
  end
end
```

`redirect_to_provider` keeps what the callback needs in the session and sends
the person to the vendor. `authenticate_with_provider` checks the callback,
swaps the code for tokens, asks who signed in and returns an `auth`. An
unknown provider is a 404 because the controller says which providers sign
people in; `AnyAuth.strategy` raises `KeyError` for a name nobody configured.

### 5. Find the person

```ruby
class User < ApplicationRecord
  has_many :identities

  def self.from_any_auth(auth)
    identity = Identity.find_by(provider: auth.provider, uid: auth.uid)
    return identity.user if identity
    return unless auth.info.email_verified

    find_by(email: auth.info.email)&.tap do |user|
      user.identities.create!(provider: auth.provider, uid: auth.uid)
    end
  end
end
```

Key a person on `provider` and `uid`. Link to an existing account by email only
when `auth.info.email_verified` is true: AnyAuth sets it only when the vendor
can vouch for the mailbox, which is stricter than the vendor's own flag (see
[Google](docs/strategies/google.md) and [Microsoft](docs/strategies/microsoft.md)).

### 6. Add the buttons

```erb
<%= button_to "Sign in with Google", auth_path(:google), form: { data: { turbo: false } } %>
<%= button_to "Sign in with Microsoft", auth_path(:microsoft), form: { data: { turbo: false } } %>
```

The sign-in starts with a `POST`, and not through Turbo: the browser has to
follow the redirect to the vendor itself.

### Coming back to where they were

Anything passed as `params:` comes back on the `auth`:

```ruby
def create
  redirect_to_provider @strategy, redirect_uri: auth_callback_url(params[:provider]),
    params: { return_to: params[:return_to] }
end

def callback
  auth = authenticate_with_provider(@strategy)
  # …
  redirect_to url_from(auth.params["return_to"]) || root_path
end
```

`params:` goes through the session as JSON, so its keys come back as strings.
`url_from` keeps the redirect on your own host.

## Connect to a vendor's API

The same two helpers connect an account at a vendor, here Shopify, whose
sign-in needs the shop's address first.

```ruby
config.provider :shopify, client_id: ENV["SHOPIFY_CLIENT_ID"],
  client_secret: ENV["SHOPIFY_CLIENT_SECRET"], scope: "read_orders"
```

### Ask for the fields

A strategy is an ActiveModel. Its attributes are what a person types before
signing in:

```ruby
AnyAuth.strategy_class(:shopify).attribute_names   # => ["shop"]
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
class ShopsController < ApplicationController
  include AnyAuth::ControllerHelpers

  def new
    @strategy = AnyAuth.strategy(:shopify)
  end

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
    auth = authenticate_with_provider(shopify)

    Current.account.shops.create!(credentials: shopify.attributes.merge(auth.credentials))
    redirect_to shops_path
  end
end
```

`authenticate_with_provider` puts the shop back on the strategy, so
`shopify.attributes` is what was typed. Permit the attribute names and nothing
else. `Economic` and `Adversus` have fields and no sign-in at all: check
`valid?` and store `strategy.attributes`.

### Store and refresh the credentials

Store `auth.credentials` (encrypted), and renew it before each use:

```ruby
class Shop < ApplicationRecord
  serialize :credentials, coder: JSON
  encrypts :credentials

  def access_token
    renewed = strategy.refresh(credentials)
    update!(credentials: renewed) if renewed != credentials
    renewed["access_token"]
  end

  private

  def strategy
    AnyAuth.strategy(:shopify, shop: credentials["shop"])
  end
end
```

`refresh` asks the vendor only when the token runs out within two minutes, and
keeps a refresh token the vendor did not replace. A vendor that rotates its
refresh token, as Shopify does, must not be refreshed twice at once. How a
vendor wants the token sent on an API call is on its
[strategy page](docs/strategies).

### One client per customer

Options given to `AnyAuth.strategy` win over the configured ones, so a client
can come from your database:

```ruby
config.provider :shopify, scope: "read_orders"

AnyAuth.strategy(:shopify, client_id: tenant.client_id, client_secret: tenant.client_secret)
```

## Reference

### Providers

```ruby
config.provider :google, client_id: -> { ENV["GOOGLE_CLIENT_ID"] }
config.provider :google_drive, from: :google, scope: "https://www.googleapis.com/auth/drive.file"
config.provider :google_workspace, strategy: :google, client_id: "…", client_secret: "…"

AnyAuth.providers   # => ["google", "google_drive", "google_workspace"]
```

| | |
| --- | --- |
| `from:` | another provider's strategy and options, here the same Google client asking for Drive |
| `strategy:` | another provider's code only, with options of its own |
| a callable value | asked each time a strategy is built |
| `scope:` | replaces the strategy's default; OpenID Connect always adds `openid` |

Options sent to the vendor are declared per strategy (`scope` everywhere,
`prompt` and `login_hint` for Google and Microsoft, and others on each
strategy page). An unknown option raises `ActiveModel::UnknownAttributeError`
when the strategy is built.

### Controller helpers

| | |
| --- | --- |
| `redirect_to_provider(strategy, redirect_uri:, params: {})` | keeps the sign-in in the session and redirects to the vendor |
| `authenticate_with_provider(strategy)` | checks the callback, swaps the code and returns the `auth` |
| `any_auth_params(strategy)` | the `params:` you passed, readable before the code is swapped and when the sign-in fails |

The sign-in is kept for ten minutes and used once. One at a time: a second
replaces the first.

### What comes back

| | |
| --- | --- |
| `auth.provider` | the name the provider is configured under |
| `auth.uid` | who the vendor's token is for, as the vendor identifies them |
| `auth.info` | `name`, `email`, `image`, nil where the vendor does not say; `email_verified`, false unless it vouches |
| `auth.credentials` | `access_token`, and `refresh_token` and `expires_at` (ISO 8601) when sent |
| `auth.raw` | what the vendor said about who signed in: the ID token's claims, or its answer without the tokens |
| `auth.params` | what you passed as `params:` |

`uid` is a person, except at Shopify, whose tokens belong to a shop, and at
Tavle, where it is one person in one company:

| Strategy | `uid` | In `raw` |
| --- | --- | --- |
| Google | `sub` | `hd`, the Workspace domain |
| Microsoft | `<tenant id>:<object id>` | `tid`, the tenant |
| Apple | `sub` | `is_private_email` |
| HubSpot | the user's id | `hub_id`, `hub_domain` |
| Relatel | the employee's id | `company_id` |
| Tavle | the membership's id | `company` |
| Shopify | the shop's domain | the granted scope |

### Errors

| Error | Means |
| --- | --- |
| `InvalidCallback` | the callback is not ours: wrong state, no code, a bad signature, nothing under way |
| `Declined` | the person or the vendor said no (`error=` on the callback); `code` holds it |
| `Unauthorized` | the vendor refused the code, the refresh or the ID token; `code` holds its reason, such as `invalid_grant` |
| `Unavailable` | a timeout, a server error, an answer that cannot be read |
| `RateLimited` | an `Unavailable` asking you to slow down |

All are `AnyAuth::Error`. Mistakes in setup are ordinary Ruby errors: an
unconfigured provider is a `KeyError`.

### Strategies

| Strategy | Kind | |
| --- | --- | --- |
| [`Google`](docs/strategies/google.md) | OpenID Connect | sign-in and Google APIs |
| [`Microsoft`](docs/strategies/microsoft.md) | OpenID Connect | work, school and personal accounts |
| [`Apple`](docs/strategies/apple.md) | OpenID Connect | signed client secret; the callback is a `POST` you send on |
| [`Hubspot`](docs/strategies/hubspot.md) | OAuth 2 | one more request, to name the user |
| [`Relatel`](docs/strategies/relatel.md) | OAuth 2 | one more request, to name the employee |
| [`Tavle`](docs/strategies/tavle.md) | OAuth 2 | one more request, to name the member |
| [`Shopify`](docs/strategies/shopify.md) | OAuth 2 with a field | per-shop endpoints, signed callback |
| [`Economic`](docs/strategies/economic.md), [`Adversus`](docs/strategies/adversus.md) | fields only | |
| [`Developer`](docs/strategies/developer.md) | a field | sign in as anyone; development only, loaded on request |

## Writing a strategy

A new OAuth 2 vendor is its endpoints and one request to learn who signed in:

```ruby
class Pipedrive < AnyAuth::Strategies::OAuth
  def client_options
    { site: "https://api.pipedrive.com", authorize_url: "https://oauth.pipedrive.com/oauth/authorize",
      token_url: "https://oauth.pipedrive.com/oauth/token" }
  end

  private

  def identity(access_token, _session)
    user = get(access_token, "/v1/users/me")["data"]
    { uid: user["id"].to_s, info: AnyAuth::Info.new(name: user["name"], email: user["email"]) }
  end
end
```

[Adding a strategy](docs/adding-a-strategy.md) covers OpenID Connect vendors,
fields, PKCE, the steps you can override and how to test it.
[How a sign-in works](docs/how-a-sign-in-works.md) says what is kept and
checked along the way.

## Coming from OmniAuth

| OmniAuth | AnyAuth |
| --- | --- |
| `provider :google_oauth2, id, secret` | `config.provider :google, client_id:, client_secret:` |
| `/auth/:provider` and its callback, by the middleware | two routes and actions of your own |
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

For development, the [`Developer`](docs/strategies/developer.md) strategy signs
in as any email without a vendor.

## Without the helpers

Outside a controller, call `request_phase` and `callback_phase` yourself; see
[How a sign-in works](docs/how-a-sign-in-works.md#without-the-helpers).

## Limits

- No SAML or OAuth 1. A callback that arrives as a cross-site `POST` is sent
  on to a `GET` by your app, as [Apple's](docs/strategies/apple.md) is.
- Endpoints are written in each strategy; there is no discovery.
- The ID token is read from the token endpoint over TLS and checked for
  issuer, audience, expiry and nonce. Its signature is not verified, which
  OpenID Connect allows for that path only.
- `info` is a name, an email, whether it is vouched for, and a picture.
