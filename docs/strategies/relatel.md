# Relatel

OAuth 2 for the Relatel telephony API, with one difference from the standard.

## Configure

```ruby
config.provider :relatel, client_id: "…", client_secret: "…"
```

It declares no options beyond `scope`.

## The vendor echoes no state

Relatel does not send the `state` parameter back to the callback, so the
strategy cannot require it. A state that does come back must match. Beyond
that the strategy only requires a stored request; with `ControllerHelpers`
that means one started in this browser within the last ten minutes. If you
store requests yourself, enforce that.

The consequence: while someone's Relatel sign-in is under way, a callback
address forged by another party and opened in that same browser would be
accepted, and could connect that person to the forger's Relatel company.
Treat a Relatel connection as something to confirm on screen (show the company
that was connected) before it is used.

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
