# Adding a strategy

A strategy is a class under `AnyAuth::Strategies` that turns one vendor's
sign-in into an `AnyAuth::Auth`. Pick the base that matches the vendor, write
what differs, and test it against canned HTTP answers.

| The vendor | Inherit from | You write |
| --- | --- | --- |
| hands back tokens, and you ask its API who signed in | `OAuth` | `client_options`, `identity` |
| hands back an ID token (OpenID Connect) | `OpenIDConnect` | `client_options`, `valid_issuer?` |
| gives the person keys to paste, no sign-in | `Base` | attributes and validations |

Read [How a sign-in works](how-a-sign-in-works.md) first if you want to know
what the base classes already check.

## An OAuth 2 vendor

The endpoints, and one request to learn who signed in:

```ruby
module AnyAuth
  module Strategies
    class Pipedrive < OAuth
      def client_options
        {
          site: "https://api.pipedrive.com",
          authorize_url: "https://oauth.pipedrive.com/oauth/authorize",
          token_url: "https://oauth.pipedrive.com/oauth/token",
        }
      end

      private

      def identity(access_token, _session)
        user = get(access_token, "/v1/users/me")["data"]
        raise Unauthorized, "#{provider} returned no user" if user.blank?

        {
          uid: user["id"].to_s,
          info: Info.new(name: user["name"], email: user["email"]),
          raw: user,
        }
      end
    end
  end
end
```

- `client_options` go to the [oauth2 gem](https://gitlab.com/ruby-oauth/oauth2)'s
  `OAuth2::Client`. A relative `authorize_url` or `token_url` is joined to `site`.
- `get(access_token, path)` sends the token as a Bearer header, turns refusals
  and outages into AnyAuth errors, and refuses an answer that is not a JSON
  object. The hash it returns keeps the vendor's own keys.
- `identity` answers `uid`, and `info` and `raw` if it can. Without it, `uid` is
  nil.
- Use `provider` in messages, not the vendor's name: the same class can be
  configured under several names.

Register it with its class, or by name if it lives in `AnyAuth::Strategies`:

```ruby
config.provider :pipedrive, client_id: "…", client_secret: "…"
config.provider :crm, strategy: AnyAuth::Strategies::Pipedrive, client_id: "…", client_secret: "…"
```

## An OpenID Connect vendor

The ID token says who signed in, so there is no extra request. Define where the
token may come from; the base checks audience, expiry and the nonce:

```ruby
class Okta < OpenIDConnect
  attribute :domain, :string

  def client_options
    {
      site: "https://#{domain}",
      authorize_url: "/oauth2/v1/authorize",
      token_url: "/oauth2/v1/token",
    }
  end

  private

  def valid_issuer?(claims)
    claims["iss"] == "https://#{domain}"
  end
end
```

`valid_issuer?` is required: without it every sign-in raises
`NotImplementedError`. The ID token's signature is not verified (it comes
straight from the token endpoint over TLS), so the issuer check is what stops a
token from somewhere else.

By default `uid` is the `sub` claim and `info` is `name`, `email` and `picture`,
with `email_verified` false. Override `info_from(claims)` to say when the
vendor vouches for an address, or `identity_from(claims)` for another `uid`, as
Microsoft does with `tid` and `oid`. Use `fetch_claim(claims, name)` for a
claim that must be there.

## A vendor with fields

Anything the person must type first is an ActiveModel attribute, validated
like any model. It is kept across the trip to the vendor and put back on the
strategy in the callback:

```ruby
attribute :domain, :string
validates :domain, format: { with: /\A[a-z0-9-]+\.okta\.com\z/ }
```

If a field decides where the person is sent, check it in `client_options` too,
so a strategy nobody validated cannot send anyone to another host. Shopify
raises `ArgumentError` there.

A vendor with keys and no sign-in at all inherits from `Base` and has only
attributes; the app stores `strategy.attributes`. See `Economic`.

## Options sent to the vendor

Declare each authorize parameter an app may set:

```ruby
authorize_option :prompt, :login_hint
```

They become accessors, can be configured or passed to `AnyAuth.strategy`, and
are added to the authorize URL when present. `scope` is declared for every
OAuth strategy.

## Switches

| | Default | Change it |
| --- | --- | --- |
| PKCE (S256) | off for `OAuth`, on for `OpenIDConnect` | `self.pkce = true` or `false` in the class; `pkce: true` per provider |
| how the client authenticates | id and secret in the request body | `auth_scheme: :basic_auth` in `client_options` |
| the default scope | none for `OAuth`, `email profile` for `OpenIDConnect` | a `scope:` default in an overridden `request_phase`, as Apple does |

Turn PKCE on when the vendor's metadata lists `S256` under
`code_challenge_methods_supported`, as Relatel's does.

## Steps you can override

Each is private; override it and call `super` where the base's work still
applies.

| Step | Base does | Override for |
| --- | --- | --- |
| `verify(params, session)` | a sign-in is under way, the state matches, no `error=`, a code is present | a signed callback (Shopify's HMAC) |
| `fetch_access_token(code, session, **params)` | swaps the code, with the PKCE verifier | extra parameters on the swap (Shopify's `expiring: 1`) |
| `identity(access_token, session)` | nothing for `OAuth`; reads the ID token for `OpenIDConnect` | saying who signed in |
| `request_phase` / `callback_phase` | the whole flow | a vendor that differs throughout (Apple adds `response_mode`, `Developer` never leaves) |

Raise AnyAuth's errors, not your own: `InvalidCallback` when the callback is
not ours, `Unauthorized` when the vendor refused or named nobody,
`Unavailable` when it could not answer. Keep tokens and vendor bodies out of
messages, and raise with `cause: nil` if you rescue something that holds them.

## Testing a strategy

Call the phases directly with string-keyed hashes and stub the vendor with
WebMock:

```ruby
class PipedriveTest < ActiveSupport::TestCase
  test "Pipedrive names the user who signed in" do
    stub_request(:post, "https://oauth.pipedrive.com/oauth/token").to_return(
      headers: { "Content-Type" => "application/json" }, body: { access_token: "token" }.to_json
    )
    stub_request(:get, "https://api.pipedrive.com/v1/users/me").to_return(
      headers: { "Content-Type" => "application/json" }, body: { data: { id: 7, name: "Mette" } }.to_json
    )
    pipedrive = AnyAuth::Strategies::Pipedrive.new(client_id: "app", client_secret: "secret")

    auth = pipedrive.callback_phase(
      { "code" => "code", "state" => "s" },
      { "state" => "s", "redirect_uri" => "https://app.test/callback" }
    )

    assert_equal "7", auth.uid
  end
end
```

For OpenID Connect, put the ID token in the token answer
(`JWT.encode(claims, nil, "none")`) and the nonce in both the claims and the
session. The gem's own tests in `test/any_auth/strategies/` cover every
strategy this way.

## Checklist

- `client_options` with the vendor's endpoints.
- `identity` (OAuth) or `valid_issuer?` (OpenID Connect).
- Fields validated, and checked again before they pick a host.
- PKCE on if the vendor supports it.
- Tests for who signed in, and for a refusal.
- A page in `docs/strategies/`: configure, at the vendor, what comes back,
  checks, calling the API. Copy an existing one.
- A row in the README's and `docs/README.md`'s strategy tables.
