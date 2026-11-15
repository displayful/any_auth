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

### 3. Add the routes

```ruby
# config/routes.rb
scope "auth/:provider", module: :auth, as: :auth do
  resource :authorization, only: :create
  resource :callback, only: :show
end
```

Two resources: `POST /auth/google/authorization` starts the sign-in, and
`GET /auth/google/callback` is where the vendor sends the person back.

### 4. Write the controllers

The examples build on the Rails 8 authentication generator
(`bin/rails generate authentication`), which gives you `start_new_session_for`
and `after_authentication_url`.

```ruby
# app/controllers/auth/base_controller.rb
class Auth::BaseController < ApplicationController
  include AnyAuth::ControllerHelpers

  allow_unauthenticated_access
  before_action :set_strategy
  rescue_from AnyAuth::Error, with: :refused

  private
    def set_strategy
      @strategy = AnyAuth.strategy(params[:provider])
    end

    def refused
      redirect_to new_session_path, alert: "Try another way to sign in."
    end
end
```

```ruby
# app/controllers/auth/authorizations_controller.rb
class Auth::AuthorizationsController < Auth::BaseController
  def create
    redirect_to_provider @strategy, redirect_uri: auth_callback_url(params[:provider])
  end
end
```

```ruby
# app/controllers/auth/callbacks_controller.rb
class Auth::CallbacksController < Auth::BaseController
  def show
    if user = User.from_any_auth(authenticate_with_provider(@strategy))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      refused
    end
  end
end
```

`redirect_to_provider` keeps what the callback needs in the session and sends
the person to the vendor. `authenticate_with_provider` checks the callback,
swaps the code for tokens, asks who signed in and returns an `auth`. A failed
or refused sign-in raises an `AnyAuth::Error`, and the person lands back on
the sign-in page.

`after_authentication_url` already returns people to the page they were
asked to sign in on: the generator keeps it in the session, and the trip to
the vendor leaves it there.

### 5. Find the person

```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy

  def self.from_any_auth(auth)
    if identity = Identity.find_by(provider: auth.provider, uid: auth.uid)
      identity.user
    elsif auth.info.email_verified
      find_by(email_address: auth.info.email)&.tap do |user|
        user.identities.create!(provider: auth.provider, uid: auth.uid)
      end
    end
  end
end
```

Key a person on `provider` and `uid`, in an `Identity` that belongs to the
user. Link to an existing account by
email only when `auth.info.email_verified` is true: AnyAuth sets it only when
the vendor can vouch for the mailbox, which is stricter than the vendor's own
flag (see [Google](docs/strategies/google.md) and
[Microsoft](docs/strategies/microsoft.md)).

### 6. Add the buttons

```erb
<%= button_to "Sign in with Google", auth_authorization_path(:google), form: { data: { turbo: false } } %>
<%= button_to "Sign in with Microsoft", auth_authorization_path(:microsoft), form: { data: { turbo: false } } %>
```

The sign-in starts with a `POST`, and not through Turbo: the browser has to
follow the redirect to the vendor itself.

### Carrying something through the sign-in

Anything passed as `params:` comes back on the `auth`, such as an invitation
the person was accepting:

```ruby
redirect_to_provider @strategy, redirect_uri: auth_callback_url(params[:provider]),
  params: { invitation: params[:invitation] }

auth = authenticate_with_provider(@strategy)
auth.params["invitation"]
```

It goes through the session as JSON, so its keys come back as strings.

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
# config/routes.rb
resources :shops, only: %i[ index new create ]
namespace :shops do
  resource :callback, only: :show
end
```

```ruby
# app/controllers/shops_controller.rb
class ShopsController < ApplicationController
  include AnyAuth::ControllerHelpers

  def new
    @strategy = AnyAuth.strategy(:shopify)
  end

  def create
    @strategy = AnyAuth.strategy(:shopify, params.expect(strategy: [ :shop ]))

    if @strategy.valid?
      redirect_to_provider @strategy, redirect_uri: shops_callback_url
    else
      render :new, status: :unprocessable_content
    end
  end
end
```

```ruby
# app/controllers/shops/callbacks_controller.rb
class Shops::CallbacksController < ApplicationController
  include AnyAuth::ControllerHelpers

  def show
    shopify = AnyAuth.strategy(:shopify)
    auth = authenticate_with_provider(shopify)

    Current.user.shops.create!(credentials: shopify.attributes.merge(auth.credentials))
    redirect_to shops_path, notice: "#{shopify.shop} is connected."
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

### Configuring each sign-in (OmniAuth's setup phase)

OmniAuth runs a `setup` proc before each phase to change a strategy's options
for that request, such as a customer's own client or IdP. In AnyAuth you build
the strategy yourself, so the setup is the arguments you build it with.
Options given to `AnyAuth.strategy` win over the configured ones:

```ruby
config.provider :shopify, scope: "read_orders"
```

```ruby
class Auth::BaseController < ApplicationController
  # …

  private
    def set_strategy
      @strategy = AnyAuth.strategy(params[:provider], **Current.account.sign_in_options)
    end
end
```

Build it the same way in both actions; a `before_action` does that. Only the
strategy's fields (such as Shopify's shop) travel to the callback with the
sign-in. Its options do not, so a client id or certificate from your database
must be looked up again, as above.

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

What `uid` is, and what each vendor puts in `raw`, is on its
[strategy page](docs/strategies).

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
| [`Saml`](docs/strategies/saml.md) | SAML 2.0 | a customer's IdP; needs ruby-saml, loaded on request |
| [`OAuth1`](docs/adding-a-strategy.md#an-oauth-1-vendor) | OAuth 1.0a | a base for OAuth 1 vendors; needs the oauth gem, loaded on request |
| [`Developer`](docs/strategies/developer.md) | a field | sign in as anyone; development only, loaded on request |

## Writing a strategy

A new OAuth 2 vendor is its endpoints and one request to learn who signed in:

```ruby
class Pipedrive < AnyAuth::Strategies::OAuth2
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
| a `setup` proc | [the arguments you build the strategy with](#configuring-each-sign-in-omniauths-setup-phase) |
| `extra.raw_info` | `auth.raw` |

- Keep your provider names: `config.provider :google_oauth2, strategy: :google`.
- Compare `uid`s before switching; each strategy page says what it is.
- `auth` is an object: `auth.uid`, not `auth["uid"]`. `credentials` has
  `access_token` where OmniAuth has `token`, and `expires_at` as ISO 8601 text.

## Testing

Stub the vendor's HTTP answers and drive your controllers:

```ruby
post auth_authorization_path(:google)
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

- A callback that arrives as a cross-site `POST` loses the session cookie.
  Apple's is sent on to a `GET` ([its page](docs/strategies/apple.md)); SAML's
  is accepted on its signature alone ([its page](docs/strategies/saml.md#the-trade-off)).
- Endpoints are written in each strategy; there is no discovery.
- The ID token is read from the token endpoint over TLS and checked for
  issuer, audience, expiry and nonce. Its signature is not verified, which
  OpenID Connect allows for that path only.
- `info` is a name, an email, whether it is vouched for, and a picture.
