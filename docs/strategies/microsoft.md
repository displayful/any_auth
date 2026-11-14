# Microsoft

OpenID Connect against Microsoft's shared `common` endpoint, so work, school
and personal accounts can all sign in.

## Configure

```ruby
config.provider :microsoft, client_id: ENV["MICROSOFT_CLIENT_ID"], client_secret: ENV["MICROSOFT_CLIENT_SECRET"]

# Microsoft's code with another client and other scopes
config.provider :power_bi, strategy: :microsoft, client_id: "…", client_secret: "…",
  scope: "offline_access https://analysis.windows.net/powerbi/api/Report.Read.All"
```

| Option | Sent to Microsoft | Notes |
| --- | --- | --- |
| `scope` | yes | defaults to `email profile`; `openid` is always added. Add `offline_access` for a refresh token |
| `prompt` | yes | `select_account`, `consent` or `login` |
| `login_hint` | yes | an email to prefill |
| `domain_hint` | yes | a tenant domain to skip the account picker |

## At Microsoft

Register an app in Entra with "Accounts in any organizational directory and
personal Microsoft accounts", and add your callback address as a Web redirect
URI. Under Token configuration, add the optional ID token claims `email` and
`xms_edov`. Without them `auth.info.email` is empty and no address is ever
vouched for.

## What comes back

| | |
| --- | --- |
| `auth.uid` | `<tenant id>:<object id>`. The object id alone is only unique inside its tenant |
| `auth.info.email` | the `email` claim |
| `auth.info.email_verified` | true only for a work or school tenant whose token carries `xms_edov`, Microsoft's statement that the tenant owns the address's domain. Never true for a personal account |
| `auth.credentials` | `access_token`, `expires_at`, and `refresh_token` with `offline_access` |

Microsoft's `email` claim can be set by a tenant administrator to any address,
which is why it is not trusted on its own. Key people on `auth.uid`, and link
by email only when `email_verified` is true.

## Checks

The ID token is checked for audience, expiry and nonce, and its issuer must be
`https://login.microsoftonline.com/<tid>/v2.0` for the tenant id in the same
token. Deciding which tenants may sign in at all is your app's rule, not the
strategy's.

## Calling the API

Send the access token as `Authorization: Bearer …`.
