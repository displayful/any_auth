# AnyAuth

OmniAuth's strategies, without the Rack.

A strategy is a plain Ruby object for one vendor. It knows the vendor's
endpoints, builds the address to send a person to, and turns what comes back
into credentials and, for sign-in, an identity. Your controller calls it
through two helpers, so Rails' own sign-in, CSRF protection and tenancy apply
to every step. A strategy never touches a request, a session or a database.

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
| A gem per vendor | A class per vendor: about twenty lines for plain OAuth 2 |

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

That is the whole integration. `redirect_to_provider` remembers the sign-in in
the Rails session for ten minutes and sends the person off;
`authenticate_with_provider` takes it back, checks the callback against it and
answers the `auth`. The route constraint names the providers people may sign
in with: the registry can also hold providers you only connect APIs through,
and those must not get a sign-in address.

### Carrying something of your own across

Pass `params:` and read it from the result, as you would `omniauth.params`:

```ruby
redirect_to_provider strategy, redirect_uri: callback_url, params: { return_to: params[:return_to] }

auth = authenticate_with_provider(strategy)
auth.params["return_to"]
```

`provider_params(strategy)` reads the same values before anything is swapped
with the vendor, for a check that has to come first or for knowing where a
failed sign-in started. Values come back through the session, so keys are
strings.

### What it needs from your app

- Ruby 3.4 and Rails 8, with a session.
- The callback on the same host the person left from, arriving as a top-level
  `GET`, so the session cookie comes with it.
- The button that starts it must not be a Turbo submission
  (`data: { turbo: false }`), or the browser fetches the vendor's page in the
  background and fails.
- One sign-in per provider at a time in a browser: a second tab replaces the
  first, and reloading the callback is an `InvalidCallback`.

## One place for providers

`config.provider` names a provider and holds its defaults. `AnyAuth.strategy`
builds one, and whatever you pass then wins over the entry.

```ruby
AnyAuth.configure do |config|
  config.provider :google, client_id: -> { ENV["GOOGLE_CLIENT_ID"] }, client_secret: -> { ENV["GOOGLE_CLIENT_SECRET"] }

  # the same client, used for something else. A scope you set replaces "email profile"
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
`ActiveModel::UnknownAttributeError` the first time that strategy is built. A
strategy name that does not exist, or a `from:` nobody configured, fails
straight away in the initializer. To declare an option in a strategy of your
own, write `authorize_option :audience`.

Key a person on `auth.provider` and `auth.uid`, never on the email. Link to an
existing account by email only when `auth.info.email_verified` is true: it
means the vendor vouches that the person owns the address, which is stricter
than the vendor's own `email_verified` claim.

## Connecting an API instead of signing in

The same two calls, with a provider that carries the scope you need. What you
store is `auth.credentials`.

```ruby
config.provider :hubspot, client_id: "…", client_secret: "…", scope: "crm.objects.deals.read"
```

```ruby
redirect_to_provider AnyAuth.strategy(:hubspot), redirect_uri: callback_url

auth = authenticate_with_provider(AnyAuth.strategy(:hubspot))
auth.credentials
# => { "access_token" => "…", "refresh_token" => "…", "expires_at" => "2026-11-13T10:00:00Z" }
```

## Keeping the credentials working

AnyAuth is not a client for the vendor's API: how each vendor wants its token
sent is on [its page](docs/strategies). What it does keep for you is the token
itself.

```ruby
credentials = strategy.refresh(credentials)   # unchanged if still good; renewed if about to expire
save(credentials)
```

| | |
| --- | --- |
| `expired?(credentials)` | whether the access token runs out within two minutes |
| `refresh(credentials)` | renews when `expired?`, and answers the credentials either way |
| `refresh!(credentials)` | asks the vendor for a new token now |

Credentials are the hash `auth.credentials` gave you. `expires_at` may be the
text it wrote or a number of seconds, and string or symbol keys both work.
Expired credentials with no refresh token cannot be renewed: that is an
`AnyAuth::Unauthorized`, and the person has to sign in again.

What comes back is the whole hash, with a refresh token the vendor did not
replace kept in place. A vendor that rotates its refresh token, as Shopify
does, must not be refreshed twice at once: check `expired?`, take a lock or
reload, and then refresh. Strategies with nothing to renew answer the
credentials unchanged.

## Vendors that ask for something first

A strategy is an ActiveModel, and its attributes are the fields a person
types. Shopify needs the shop before it can build an address:

```ruby
shopify = AnyAuth.strategy(:shopify, shop: "mystore")
shopify.valid?   # true. False, with an error on :shop, for anything that is not a shop
shopify.shop     # "mystore.myshopify.com"
```

### Where the fields are

They are ordinary attributes, so each step is a call you already know:

```ruby
AnyAuth.strategy_class(:shopify).attribute_names   # => ["shop"]   what to ask for
AnyAuth.strategy_class(:shopify).fields?           # => true       whether to ask at all

strategy = AnyAuth.strategy(:shopify, params.expect(strategy: [:shop]))   # what was typed
strategy.shop          # => "mystore.myshopify.com"                       one of them
strategy.attributes    # => { "shop" => "mystore.myshopify.com" }         all of them, to store
```

`AnyAuth.strategy` takes attributes the way `Model.new` does: a hash, or
permitted parameters straight from the controller. Parameters that were not
permitted raise `ActiveModel::ForbiddenAttributesError`, so a posted
`client_secret` can never reach the strategy by accident. Permit
`attribute_names` and nothing else.

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

A plain Rails form builder only wraps an invalid field in `field_with_errors`;
printing the message is yours to do, as above, unless your app's own builder
shows it for you.

`strategy.class.attribute_names` lists the fields, and
`strategy.class.fields?` says whether there are any, for a page that draws
whichever vendor it is given. The gem does not know which fields are secret;
choose `password_field` for those in your own view.

### Fields, then a round trip

Validate, then leave. The fields come home with the person: the helpers
remember them and put them back on the strategy, so the callback builds it
with none.

```ruby
class ShopsController < ApplicationController
  include AnyAuth::ControllerHelpers

  def new
    @strategy = AnyAuth.strategy(:shopify)
  end

  def create
    @strategy = AnyAuth.strategy(:shopify, fields)

    if @strategy.valid?
      redirect_to_provider @strategy, redirect_uri: callback_shops_url
    else
      render :new, status: :unprocessable_content
    end
  end

  def callback
    shopify = AnyAuth.strategy(:shopify)
    auth    = authenticate_with_provider(shopify)

    current_account.shops.create!(credentials: shopify.attributes.merge(auth.credentials))
  end

  private

  def fields
    params.expect(strategy: AnyAuth.strategy_class(:shopify).attribute_names)
  end
end
```

What you store is the fields and the tokens together. Later, build the
strategy from the fields in that hash and hand the whole hash to `refresh`:

```ruby
credentials = shop.credentials
shopify     = AnyAuth.strategy(:shopify, credentials.slice(*AnyAuth.strategy_class(:shopify).attribute_names))
shop.update!(credentials: shopify.refresh(credentials))
```

A strategy refuses to go anywhere on a shop that is not one:
`redirect_to_provider` raises `ArgumentError` if you skipped `valid?`.

### Fields and no round trip

Some vendors have you paste a token or a login from their settings page.
Those strategies (`Economic`, `Adversus`) have no phases at all, so do not pass
them to `redirect_to_provider`. Show the same form, check `valid?`, and
store `strategy.attributes`. To find out whether the vendor accepts what was
typed, call its API once with them before you save.

## What comes back

`callback_phase` answers an `AnyAuth::Auth`:

| | |
| --- | --- |
| `auth.provider` | the name the provider is configured under: `"google"`, `"shopify"` |
| `auth.uid` | who signed in, as the vendor identifies them. Stable; key a person on it |
| `auth.info` | what is known about them. Always there; empty when the vendor says nothing |
| `auth.credentials` | `access_token`, and `refresh_token` and `expires_at` when the vendor sends them |
| `auth.raw` | what the vendor said, as it said it: the ID token's claims, or its answer about the account |
| `auth.params` | what you passed as `params:` when the person left |

`auth.info` is an `AnyAuth::Info` with the same four members for every vendor.
Each is nil when the vendor does not say, except `email_verified`, which is then false:

| | |
| --- | --- |
| `name` | a name to show: the person's, or the account's |
| `email` | their address |
| `email_verified` | whether the vendor vouches that they own it. False unless the strategy is sure |
| `image` | the address of a picture |

`uid` is always who signed in, never the account they opened. A vendor with
tenants says which one in `auth.raw`, and your app decides what to key on:

| Strategy | `uid`: who signed in | In `raw`: what they opened |
| --- | --- | --- |
| Google | the person's `sub` | `hd`, their Workspace domain |
| Microsoft | tenant id and object id | `tid`, their tenant |
| HubSpot | the user's id | `hub_id` and `hub_domain`, the portal |
| Relatel | the employee's id | `company_id`, the company |
| Shopify | the shop's domain | nothing more: an offline token has no person, so the shop is who signed in |
| Developer | the email typed | nothing |

So a connection to a company's HubSpot is keyed on `auth.raw["hub_id"]`, and
two colleagues signing in to the same portal are the same connection. Each
[strategy's page](docs/strategies) lists what its `raw` holds.

## Errors

Everything a vendor or a callback can cause is an `AnyAuth::Error`. Rescue that
one class, or tell them apart. Mistakes in your own setup are ordinary Ruby
errors: an unconfigured provider name is a `KeyError`, an unknown option an
`ActiveModel::UnknownAttributeError`.

| Error | Means | Usually |
| --- | --- | --- |
| `InvalidCallback` | the callback is not ours: wrong state, no code, a bad signature | start again |
| `Declined` | the vendor sent `error=` on a callback that is ours; `code` is what it sent | show why |
| `Unauthorized` | the vendor refused the code swap, the refresh, the who-is-this request or the ID token | sign in again |
| `Unavailable` | any other failure: a timeout, a server error, an answer we cannot read | retry later |
| `RateLimited` | an `Unavailable` that asks you to slow down | retry later |

## Strategies included

Each has its own page under [docs/strategies](docs/strategies): what to
configure, what the vendor needs, what comes back and what is unusual.

| Strategy | Kind | Notes |
| --- | --- | --- |
| [`Google`](docs/strategies/google.md) | OpenID Connect | links by email for Gmail and Workspace addresses |
| [`Microsoft`](docs/strategies/microsoft.md) | OpenID Connect | work, school and personal accounts; `uid` is tenant and object id |
| [`Hubspot`](docs/strategies/hubspot.md) | OAuth 2 | one more request, to name the user |
| [`Relatel`](docs/strategies/relatel.md) | OAuth 2 | the vendor echoes no state |
| [`Shopify`](docs/strategies/shopify.md) | OAuth 2 with a field | per-shop endpoints, signed callback, expiring tokens |
| [`Economic`](docs/strategies/economic.md), [`Adversus`](docs/strategies/adversus.md) | fields only | pasted tokens or a login |
| [`Developer`](docs/strategies/developer.md) | a field and a trip to yourself | type an email and be that person; for development only |

`Developer` is not loaded unless you ask for it. Require it and register it
only where it is safe:

```ruby
if Rails.env.development?
  require "any_auth/strategies/developer"
  config.provider :developer
end
```

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
porting one starts with copying that hash. A class of your own can live
anywhere in your app: register it with `config.provider :pipedrive, strategy:
Pipedrive, …`. A symbol is looked up among the gem's strategies.

When a vendor is unusual, override only the step that differs and call
`super`:

| Step | Override when | Example |
| --- | --- | --- |
| `verify(params, session)` | the callback needs more than its state | Shopify's signature and shop |
| `exchange(code, session)` | the code swap takes extra parameters | Shopify's `expiring: 1` |
| `identity(token, session)` | the answer says who signed in | `OpenIDConnect` |
| `state_echoed?(params, session)` | the vendor sends no state back | Relatel |

For a vendor people sign in with, inherit from `OpenIDConnect` and answer
`identity_from(claims)` with `{ uid:, info: }`. The audience, expiry and nonce
are checked before it is called; checking the issuer is that method's job,
since vendors name theirs differently.

## Coming from OmniAuth

- **Provider names are yours.** `config.provider :google_oauth2, strategy:
  :google` keeps the values already in your `provider` column and the callback
  addresses already registered with the vendor.
- **Check `uid` before you switch.** Google's is the `sub`, as
  omniauth-google-oauth2 uses. Microsoft's is `<tenant id>:<object id>`,
  HubSpot's the user id and Relatel's the employee id; compare them with what
  your OmniAuth gems stored, since existing rows may need rewriting.
- **`auth` is an object, not a hash.** `auth.uid`, not `auth["uid"]`.
- **`credentials` has other keys:** `access_token` where OmniAuth has `token`,
  `expires_at` as ISO 8601 text, and no `expires`.
- **`extra.raw_info` is `auth.raw`.** `info` has `name`, `email`,
  `email_verified` and `image` only.
- **`omniauth.origin` and `omniauth.params`** become `params:` on
  `redirect_to_provider`, read back as `auth.params`.
- **A person cancelling at the vendor** is an `AnyAuth::Declined`.

## Testing

There is no test mode. Stub the vendor's HTTP answers and drive your real
controllers:

```ruby
post auth_path(:google)
sent = Rack::Utils.parse_query(URI(response.location).query)

claims = { sub: "g-1", email: "mette@gmail.com", email_verified: true,
           iss: "https://accounts.google.com", aud: "your-client-id",
           exp: 1.hour.from_now.to_i, nonce: sent["nonce"] }
stub_request(:post, "https://oauth2.googleapis.com/token").to_return(
  headers: { "Content-Type" => "application/json" },
  body: { access_token: "token", id_token: JWT.encode(claims, nil, "none") }.to_json
)

get auth_callback_path(:google, code: "code", state: sent["state"])
```

The ID token can be unsigned in a test, because the gem reads it from the
token endpoint and does not check its signature.

## Outside a Rails controller

The helpers are a thin layer over two plain methods, which take and return
values and touch nothing else:

```ruby
request = strategy.request_phase(redirect_uri: "https://app.test/callback")
request.url       # where to send the person
request.session   # what to keep until they come back

auth = strategy.callback_phase(query, kept)   # both string-keyed hashes
```

`query` is what the vendor sent in the callback's query string, and `kept` is
`request.session` from before. Keeping it somewhere safe, for a limited time
and for one use, is then yours to do.

## What it does not do

- **SAML, OAuth 1, or callbacks that arrive as a cross-site `POST`** (Sign in
  with Apple's `form_post`). The phases leave room for them; none is built.
- **Discovery or key sets.** Endpoints are written in the strategy. The ID
  token is read from the token endpoint over TLS and checked for audience,
  expiry, nonce and issuer; its signature is not verified, which OpenID Connect
  allows for that path only. A token that reaches you through the browser must
  not be trusted this way.
- **A full profile.** `info` is a name, an email, whether the email is vouched
  for, and a picture. Ask the
  vendor's API for anything more.
- **Your user model, your session or your routes.** Those stay yours.

If you need a vendor that has an OmniAuth gem and none of the above bothers
you, OmniAuth is less work. AnyAuth is for when the sign-in has to know what
your app knows.
