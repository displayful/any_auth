# Relatel

OAuth 2 for the Relatel telephony API, with one difference from the standard.

## Configure

```ruby
config.provider :relatel, client_id: "…", client_secret: "…"
```

It declares no options beyond `scope`.

## The vendor echoes no state

Relatel does not send the `state` parameter back to the callback, so the
strategy cannot compare it. It still requires that a sign-in at Relatel was
started in this browser within the last ten minutes, and nothing more.

The consequence: while someone's Relatel sign-in is under way, a callback
address forged by another party and opened in that same browser would be
accepted, and could connect that person to the forger's Relatel company.
Treat a Relatel connection as something to confirm on screen (show the company
that was connected) before it is used.

## What comes back

| | |
| --- | --- |
| `auth.uid`, `auth.info` | nil |
| `auth.credentials` | `access_token`, and `refresh_token` and `expires_at` when Relatel sends them |

## Calling the API

Send the access token as `Authorization: Bearer …`.
