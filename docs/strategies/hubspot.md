# HubSpot

OAuth 2 for the HubSpot API, plus one request after the code swap to learn who signed in.

## Configure

```ruby
config.provider :hubspot, client_id: "…", client_secret: "…",
  scope: "crm.objects.deals.read crm.objects.contacts.read"
```

| Option | Sent to HubSpot | Notes |
| --- | --- | --- |
| `scope` | yes | space-separated; HubSpot refuses the sign-in if the app does not list each scope |

## At HubSpot

Create a public app in a developer account, add your callback address as a
redirect URL, and tick the same scopes you ask for.

## What comes back

| | |
| --- | --- |
| `auth.uid` | the id of the user who signed in (`user_id`), as a string |
| `auth.info.email` | their address (`user`). HubSpot does not vouch for it, so `email_verified` is false |
| `auth.credentials` | `access_token`, `refresh_token`, `expires_at` |
| `auth.raw` | HubSpot's answer about the token: `user_id`, `user`, `hub_id`, `hub_domain`, `scopes` |

The portal they opened is `auth.raw["hub_id"]`, with its domain in
`auth.raw["hub_domain"]`. Key a connection on the portal, not on the user:
colleagues signing in to the same portal have different `uid`s.

The strategy asks HubSpot once, with the new token, whose it is
(`GET /oauth/v1/access-tokens/<access_token>`). A token HubSpot names no
user for is an `AnyAuth::AccessDenied`.

Three things follow from that request:

- The access token is in the address, as HubSpot's API requires. The gem keeps
  it out of its own error messages and attaches no underlying error, but an
  HTTP logger or APM that records outgoing addresses will see it.
- If it fails, the sign-in fails, although the code was already swapped.
- HubSpot echoes the token in its answer; `auth.raw` leaves that key out.

## Calling the API

Send the access token as `Authorization: Bearer …`. Access tokens are
short-lived, so call `refresh(credentials)` before each use and
save what it returns.
