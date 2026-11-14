# Tavle

OAuth 2 for signing in with Tavle and reading a company's boards, plus one
request after the code swap to learn who signed in.

## Configure

```ruby
config.provider :tavle, client_id: "…", client_secret: "…", scope: "profile boards:read"
```

| Option | Sent to Tavle | Notes |
| --- | --- | --- |
| `scope` | yes | `profile` is the default at Tavle; add `boards:read` for the boards API |

A PKCE challenge (S256) is always sent; Tavle refuses a sign-in without one.

## At Tavle

Register a connected app with your callback address as its redirect URI.

## What comes back

| | |
| --- | --- |
| `auth.uid` | the `sub` from `/oauth/userinfo`: the **membership**, one person in one company |
| `auth.info.name` | their name |
| `auth.info.email` | their address |
| `auth.info.email_verified` | true: a Tavle address is one somebody has clicked a link at |
| `auth.credentials` | `access_token`, `refresh_token`, `expires_at` (two hours) |
| `auth.raw` | the userinfo answer, including `company` with its `id` and `name` |

The same person in another company is another `uid`, because a token is for
one company. To recognise the person across companies, use the email.

The strategy asks Tavle once, with the new token, who signed in
(`GET /oauth/userinfo`). If that request fails the sign-in fails, although the
code was already swapped.

## Calling the API

Send the access token as `Authorization: Bearer …`. Tokens last two hours;
`refresh(credentials)` renews them.
