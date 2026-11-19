# Changelog

## Unreleased

- Requests to a vendor give up after 5 seconds connecting and 10 answering,
  instead of a minute each.

## 0.2.0

- `credentials` adds `token_type`, `scope` and `refresh_token_expires_at`.
- Expiry times are epoch seconds, not ISO 8601 text. Credentials saved by
  0.1.0 keep a text `expires_at` until their next refresh.
- `refresh` always asks the vendor, so check `expires_at` before calling it.
  `expired?` and `refresh!` are gone.

## 0.1.0

The first release: strategies for Google, Microsoft, Apple, SAML, Signicat,
HubSpot, Shopify, e-conomic, Adversus, Relatel, Tavle and a developer sign-in,
called from Rails controllers through `AnyAuth::ControllerHelpers`.
