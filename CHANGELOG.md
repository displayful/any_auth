# Changelog

## Unreleased

- `credentials` also carries `token_type`, `scope` and, when the vendor says,
  `refresh_token_expires_at`, read from `refresh_token_timeout` (the IETF draft)
  or `refresh_token_expires_in` (GitHub, Google, Shopify). HubSpot's `scopes`
  list becomes `scope`.
- `expires_at` and `refresh_token_expires_at` are epoch seconds, as oauth2 and
  OmniAuth keep them, instead of ISO 8601 text. Credentials stored by 0.1.0
  still refresh, but hold `expires_at` as text until they do: convert it with
  `Time.iso8601(expires_at).to_i` before comparing it with a number.
- `refresh(credentials)` now always asks the vendor. In 0.1.0 it asked only
  when the token was about to expire, so an app that calls it before every use
  must check `expires_at` first. `refresh!` and `expired?` are gone: when to
  refresh is the app's decision.

## 0.1.0

The first release: strategies for Google, Microsoft, Apple, SAML, Signicat,
HubSpot, Shopify, e-conomic, Adversus, Relatel, Tavle and a developer sign-in,
called from Rails controllers through `AnyAuth::ControllerHelpers`.
