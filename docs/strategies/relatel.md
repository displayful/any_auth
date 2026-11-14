# Relatel

OAuth 2 for the Relatel telephony API.

## Configure

```ruby
config.provider :relatel, client_id: "…", client_secret: "…"
```

It declares no options beyond `scope`.

## What comes back

| | |
| --- | --- |
| `auth.uid` | the id of the employee who signed in, as a string |
| `auth.info` | their `name` and `email` when Relatel gives them; `email_verified` is false |
| `auth.credentials` | `access_token`, and `refresh_token` and `expires_at` when Relatel sends them |
| `auth.raw` | the employee, as Relatel describes them, including `company_id` |

The company they belong to is `auth.raw["company_id"]`. Key a connection on
the company, not on the employee.

The strategy asks Relatel once, with the new token, who the employee is
(`GET /api/v2/employee`). If that request fails the sign-in fails, although
the code was already swapped.

## Calling the API

Send the access token as `Authorization: Bearer …`.
