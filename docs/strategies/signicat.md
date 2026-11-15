# Signicat

OpenID Connect against Signicat's eID and Wallet Hub, which signs people in
with a national eID: MitID, Norwegian or Swedish BankID, the Finnish Trust
Network, Freja, ID-porten, itsme or a one-time code by SMS.

## Configure

```ruby
config.provider :signicat,
  client_id: ENV["SIGNICAT_CLIENT_ID"], client_secret: ENV["SIGNICAT_CLIENT_SECRET"],
  domain: "acme.app.signicat.com", idp: "mitid", loa: "substantial"
```

| Option | Sent to Signicat | Notes |
| --- | --- | --- |
| `domain` | no | your Signicat domain: `<name>.sandbox.signicat.com`, `<name>.app.signicat.com` or your own. Required |
| `idp` | as `acr_values=idp:…` | one eID or a list, such as `%w[nbid sbid]` to offer a choice; without it Signicat shows every eID the client allows |
| `loa` | as `acr_values=loa:…` | the lowest level of assurance to accept: `low`, `substantial` or `high` |
| `scope` | yes | defaults to `profile`; `openid` is always added. Add `nin` for the national identity number, `idp-id` for the eID's own id |
| `prompt` | yes | `login` to skip Signicat's one-hour single sign-on |
| `login_hint` | yes | Signicat's `key:value` form, such as `nin:…` |
| `ui_locales` | yes | the language of Signicat's pages, such as `da` |

Sandbox and production are separate Signicat accounts, with their own domain,
client and secret. Configure each environment with its own.

## At Signicat

In the Dashboard, under eID and Wallet Hub, create an OIDC client, add your
callback address as a redirect URI, add a secret, and add the scopes you ask
for to its allowed scopes. By default the ID token carries only the standard
claims: to get `nin` and `idp_id` in it, set "ID Token User data" to All under
Advanced, Security. Turn on the eIDs you name in `idp`.

## What comes back

| | |
| --- | --- |
| `auth.uid` | the `sub` claim, Signicat's hash of the eID, the person's id at that eID and your Signicat organisation. It stays the same across sign-ins and across your clients, and differs per eID: the same person is someone else with MitID than with Swedish BankID |
| `auth.info.name` | the `name` claim |
| `auth.info.email` | the `email` claim, which few eIDs give |
| `auth.info.email_verified` | never true: Signicat does not document it |
| `auth.credentials` | `access_token` and `expires_at` |
| `auth.raw` | every claim in the ID token: `idp`, the eID used; `acr`, the level reached; `nin` with that scope and setting |

To know someone across eIDs, link them by `nin`, never by `sub`.

## Checks

The ID token is checked for audience, expiry and nonce, and its issuer must
be `https://<domain>/auth/open`. Because `acr_values` travels in the address
and the person can change it, the token itself must say what you asked for:
with `idp` set, its `idp` claim must be one of them, and with `loa` set, its
`acr` must be at that level or higher (`unspecified < low < substantial <
high`). A token that doesn't is an `AnyAuth::InvalidCallback`.

A person who cancels at the eID comes back with an `error`, which is an
`AnyAuth::AccessDenied`; Signicat's own code, such as `AGW-3200` (the
authentication was aborted), is in its `description` when Signicat sends one.

## Not supported

Signed or pushed authorization requests and encrypted ID tokens, which the
Finnish Trust Network requires, so FTN does not work with this strategy.
