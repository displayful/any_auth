# How a sign-in works

What happens between the button and the `auth`, what is kept in a cookie,
and what is checked on the way back.

## The two phases

```
your create action            vendor                 your callback action
──────────────────            ──────                 ────────────────────
redirect_to_provider    ──▶   person signs in   ──▶  authenticate_with_provider
  request_phase                                        callback_phase
  keeps the sign-in                                      verify
  in a cookie                                            fetch_access_token
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

`redirect_to_provider` keeps one entry in its own encrypted cookie, not in
the app's session:

```ruby
cookies.encrypted["__Host-any_auth"] = {
  "provider" => "google",           # the callback must be for the same provider
  "request" => { … },               # request.session, from above
  "attributes" => { "shop" => … },  # the strategy's fields, to put back
  "params" => { … },                # what the app passed as params:
  "expires_at" => 1763040000,       # ten minutes from now
}
```

Over HTTPS the cookie is `Secure`, `HttpOnly`, `SameSite=None` and
`Path=/`, with no `Domain`: the `__Host-` prefix makes browsers refuse it from
anywhere but your own host, so a subdomain cannot plant one. `SameSite=None`
lets it come back on a provider's cross-site `POST` (Apple, SAML); sending it
there is safe because what it holds must match the provider's answer. Over
plain HTTP, as in tests, it is a `SameSite=Lax` cookie named `any_auth`, and
`POST` callbacks do not work.

`authenticate_with_provider` deletes the cookie before anything else, so it is
used once; ignores it if it has expired or is for another provider; puts the
fields back on the strategy; and calls `callback_phase` with the request's
query string and POST body (path parameters stay out). With nothing kept,
every strategy refuses the callback, except SAML built with
`allow_idp_initiated: true`. `any_auth_params` reads `params` without
deleting the cookie.

One sign-in at a time per browser: starting a second replaces the first.

## What is checked on the way back

In this order; the first that fails raises.

| Check | Raises |
| --- | --- |
| a sign-in is under way (`redirect_uri` kept) | `InvalidCallback` |
| `state` matches, compared in constant time | `InvalidCallback` |
| no `error=` | by the vendor's code (see below) |
| a `code` is present | `InvalidCallback` |
| the vendor swaps the code (sent with `redirect_uri` and the PKCE verifier) | by the vendor's code and status (see below) |
| the answer holds an access token | `AccessDenied` |

Then the strategy's own checks: Shopify's HMAC and shop before the swap, and
for OpenID Connect, on the ID token:

| Check | Raises |
| --- | --- |
| it can be read, and is a JSON object | `InvalidCallback` |
| issued by the vendor (`valid_issuer?`) | `InvalidCallback` |
| for this client: `aud` names it, and `azp` does when there are several audiences | `InvalidCallback` |
| not expired | `InvalidCallback` |
| `nonce` matches, in constant time | `InvalidCallback` |
| `sub` (or the vendor's `uid` claim) is present | `InvalidCallback` |

The ID token's signature is not verified. It is read straight from the token
endpoint over TLS, in answer to a request authenticated with the client
secret, which [OpenID Connect Core 3.1.3.7](https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation)
allows. A token from anywhere else must be verified.

## OAuth 1

`OAuth1` asks the vendor for a request token while leaving, keeps the token
and its secret (`request_token`, `request_token_secret`) instead of a state,
and on the way back checks, in order: a sign-in is under way; `denied` naming
our token is `AccessDenied`; `oauth_token` is our token, in constant time; an
`oauth_verifier` is present. Then it swaps the verifier for an access token.

## Errors from the vendor

Every request to the vendor goes through one place, which maps what went wrong:

| What happened | Raises |
| --- | --- |
| `invalid_client`, `invalid_request`, `unsupported_grant_type`, `unsupported_response_type` | `ConfigurationError` |
| `server_error`, `temporarily_unavailable` | `Unavailable` |
| any other code, or none, with 400, 401 or 403 (`access_denied`, `invalid_grant`, `unauthorized_client`, `invalid_scope`) | `AccessDenied` |
| 429, 5xx, any other status | `Unavailable`, with `retry_after` from `Retry-After` |
| a timeout, no connection, unreadable JSON | `Unavailable` |

`code` and `description` are the vendor's own, or nil. The library adds no
codes of its own: the class says what kind of failure it was. OAuth 1 reads
`oauth_problem` and `oauth_problem_advice`. A SAML failure is always
`AccessDenied` with its status as `code`, since IdPs need not sign failures.

Messages name the provider and the vendor's code, never a token or the
vendor's body, and the original exception is dropped (`cause: nil`), because
it would carry both.

## Refreshing

`refresh(credentials)` asks the vendor for a new access token every time it is
called; when to call it is the app's to decide, from `expires_at` and
`refresh_token_expires_at`, both epoch seconds. What comes back is merged over
what was stored: a vendor that sends no new refresh token keeps the old one,
and so does a `refresh_token_expires_at` or `scope` it does not send again,
while an `expires_at` the vendor no longer sends is dropped. An `expires_at`
that 0.1.0 stored as ISO 8601 text still refreshes.

## Without the helpers

Outside a Rails controller, call the phases yourself:

```ruby
request = strategy.request_phase(redirect_uri: "https://app.test/callback")
request.url       # where to send the person
request.session   # keep it, encrypted or server-side, until they come back

auth = strategy.callback_phase(query, request.session)   # string-keyed hashes
```

Keeping `request.session` for a limited time and using it once is then yours
to do, as is giving the strategy its fields again in the callback.
