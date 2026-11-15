# How a sign-in works

What happens between the button and the `auth`, what is kept in the session,
and what is checked on the way back.

## The two phases

```
your create action            vendor                 your callback action
──────────────────            ──────                 ────────────────────
redirect_to_provider    ──▶   person signs in   ──▶  authenticate_with_provider
  request_phase                                        callback_phase
  keeps the sign-in                                      verify
  in the session                                         fetch_access_token
                                                         identity
                                                       ◀── auth
```

**`request_phase(redirect_uri:)`** builds the address to send the person to and
returns it with what the callback will need, as an `AnyAuth::Request`:

| `request.session` | Why |
| --- | --- |
| `state` | random; the vendor sends it back, proving the callback belongs to this browser |
| `redirect_uri` | must be sent again, unchanged, when the code is swapped |
| `code_verifier` | PKCE: the secret behind the `code_challenge` sent now (when PKCE is on) |
| `nonce` | OpenID Connect: must come back inside the ID token |

**`callback_phase(params, session)`** takes the callback's query and that hash,
and returns the `AnyAuth::Auth`.

## What the controller helper keeps

`redirect_to_provider` stores one entry in the Rails session:

```ruby
session[:any_auth] = {
  "provider" => "google",           # the callback must be for the same provider
  "request" => { … },               # request.session, from above
  "attributes" => { "shop" => … },  # the strategy's fields, to put back
  "params" => { … },                # what the app passed as params:
  "expires_at" => 1763040000,       # ten minutes from now
}
```

`authenticate_with_provider` takes the entry out before anything else, so it is
used once; ignores it if it has expired or is for another provider; puts the
fields back on the strategy; and calls `callback_phase` with the request's
query string and POST body (path parameters stay out). With nothing kept, the
strategy decides: OAuth and the developer strategy refuse the callback, SAML
accepts it on its signature. `any_auth_params` reads `params` without taking
the entry.

One sign-in at a time per browser: starting a second replaces the first. With
the cookie session store, two requests finishing at once can overwrite each
other's session, so a sign-in started in one tab while another request is in
flight can be lost; the person starts again.

## What is checked on the way back

In this order; the first that fails raises.

| Check | Raises |
| --- | --- |
| a sign-in is under way (`redirect_uri` kept) | `InvalidCallback` |
| `state` matches, compared in constant time | `InvalidCallback` |
| no `error=` | `Declined`, with the vendor's code |
| a `code` is present | `InvalidCallback` |
| the vendor swaps the code (sent with `redirect_uri` and the PKCE verifier) | `Unauthorized`, `RateLimited` or `Unavailable` |
| the answer holds an access token | `Unauthorized` |

Then the strategy's own checks: Shopify's HMAC and shop before the swap, and
for OpenID Connect, on the ID token:

| Check | Raises |
| --- | --- |
| it can be read, and is a JSON object | `Unauthorized` |
| issued by the vendor (`valid_issuer?`) | `Unauthorized` |
| for this client: `aud` names it, and `azp` does when there are several audiences | `Unauthorized` |
| not expired | `Unauthorized` |
| `nonce` matches, in constant time | `Unauthorized` |
| `sub` (or the vendor's `uid` claim) is present | `Unauthorized` |

The ID token's signature is not verified. It is read straight from the token
endpoint over TLS, in answer to a request authenticated with the client
secret, which [OpenID Connect Core 3.1.3.7](https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation)
allows. A token from anywhere else must be verified.

## Errors from the vendor

Every request to the vendor goes through one place, which maps what went wrong:

| What happened | Raises | `code` |
| --- | --- | --- |
| 400, 401 or 403, or an answer with no token | `Unauthorized` | the vendor's `error`, such as `invalid_grant` |
| 429 | `RateLimited` | the vendor's `error`, if any |
| any other error status | `Unavailable` | the vendor's `error`, if any |
| a timeout, no connection, unreadable JSON | `Unavailable` | nil |

Messages name the provider and the vendor's code, never a token or the
vendor's body, and the original exception is dropped (`cause: nil`), because
it would carry both.

## Refreshing

`refresh(credentials)` asks the vendor only when the stored `expires_at` is
less than two minutes away, and merges what comes back over what was stored:
a vendor that sends no new refresh token keeps the old one, and an
`expires_at` the vendor no longer sends is dropped.

## Without the helpers

Outside a Rails controller, call the phases yourself:

```ruby
request = strategy.request_phase(redirect_uri: "https://app.test/callback")
request.url       # where to send the person
request.session   # keep it, server-side or signed, until they come back

auth = strategy.callback_phase(query, request.session)   # string-keyed hashes
```

Keeping `request.session` for a limited time and using it once is then yours
to do, as is giving the strategy its fields again in the callback.
