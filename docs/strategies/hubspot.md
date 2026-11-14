# HubSpot

Plain OAuth 2 for the HubSpot API. It overrides nothing.

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
| `auth.uid`, `auth.info` | nil |
| `auth.credentials` | `access_token`, `refresh_token`, `expires_at` |

To learn which portal was connected, ask HubSpot with the token:
`GET /oauth/v1/access-tokens/<access_token>` answers its `hub_id` and domain.

## Calling the API

`authorization(credentials)` answers `{ "Authorization" => "Bearer …" }`.
Access tokens are short-lived, so call `fresh(credentials)` before each use and
save what it returns.
