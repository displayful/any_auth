# AnyAuth documentation

Start with the [README](../README.md) for what AnyAuth is and how a round trip
works. These pages go one level down.

## Strategies

Each page says what to configure, what the vendor needs from you, what comes
back, and what is unusual about it.

| Strategy | Kind | For |
| --- | --- | --- |
| [Google](strategies/google.md) | OpenID Connect | signing in, and Google APIs |
| [Microsoft](strategies/microsoft.md) | OpenID Connect | signing in, and Microsoft APIs |
| [Apple](strategies/apple.md) | OpenID Connect | signing in; the callback is a `POST` |
| [HubSpot](strategies/hubspot.md) | OAuth 2 | the HubSpot API |
| [Relatel](strategies/relatel.md) | OAuth 2 | the Relatel API |
| [Tavle](strategies/tavle.md) | OAuth 2 | signing in with Tavle, and the boards API |
| [Shopify](strategies/shopify.md) | OAuth 2 with a field | a shop's Admin API |
| [e-conomic](strategies/economic.md) | fields only | the e-conomic API |
| [Adversus](strategies/adversus.md) | fields only | the Adversus API |
| [Developer](strategies/developer.md) | a field and a trip to yourself | signing in locally, with no vendor |

## The three kinds

- **OAuth 2** strategies send the person to the vendor and come back with
  credentials. `auth.uid` is who signed in; which account that opened is in
  `auth.raw`. They send a PKCE challenge when the strategy switches it on, as
  Relatel and Tavle do, or when configured with `pkce: true`.
- **OpenID Connect** strategies are OAuth 2 plus an answer to who signed in.
  They always ask for `openid`, send a nonce and (except to Apple) a PKCE challenge, and read
  `auth.uid` and `auth.info` from the ID token.
- **Fields-only** strategies (e-conomic, Adversus) have no round trip. The person types what the
  vendor gave them, and `strategy.attributes` is what you store.

Every strategy answers `refresh(credentials)`, which renews what is about to
expire and leaves everything else alone. How a vendor wants its credentials
sent on an API call is on its page; sending them is your client's job.
