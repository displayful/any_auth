# Google

OpenID Connect. Use it to sign people in with Google, to reach a Google API on
their behalf, or both.

## Configure

```ruby
config.provider :google, client_id: ENV["GOOGLE_CLIENT_ID"], client_secret: ENV["GOOGLE_CLIENT_SECRET"]

# the same client, asking for a Google API as well
config.provider :google_drive, from: :google,
  scope: "https://www.googleapis.com/auth/drive.file", access_type: "offline", prompt: "consent"
```

| Option | Sent to Google | Notes |
| --- | --- | --- |
| `scope` | yes | defaults to `email profile`; `openid` is always added |
| `access_type` | yes | `offline` to be given a refresh token |
| `prompt` | yes | `consent` makes Google hand out a refresh token again; `select_account` shows the chooser |
| `hd` | yes | hints a Workspace domain; it is a hint, so check `auth.info` yourself |
| `login_hint` | yes | an email to prefill |

## At Google

Create an OAuth client of type "Web application" in the Google Cloud console
and add your callback address as an authorised redirect URI.

## What comes back

| | |
| --- | --- |
| `auth.uid` | the `sub` claim: stable for this person across your client |
| `auth.info.email` | the `email` claim |
| `auth.info.email_verified` | true only when Google says the address is verified **and** it is a Gmail address or the token names a Workspace domain (`hd`) |
| `auth.credentials` | `access_token`, `expires_at`, and `refresh_token` when you asked for `access_type: "offline"` |

The stricter `email_verified` is deliberate. Google marks many addresses it
does not host as verified; only for Gmail and Workspace does it speak for the
mailbox. Link an existing account by email only when this is true.

## Checks

The ID token is read from the token endpoint and checked for audience (your
client id), expiry, the nonce sent with this request, and issuer
(`accounts.google.com`). A token that fails is an `AnyAuth::Unauthorized`.

## Calling the API

`authorization(credentials)` answers `{ "Authorization" => "Bearer …" }`.
Access tokens last about an hour; `fresh(credentials)` renews them when a
refresh token is stored.
