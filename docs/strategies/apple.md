# Apple

OpenID Connect, with three things of Apple's own: the client secret is signed
with your key, the callback arrives as a `POST`, and the name is sent once.

## Configure

```ruby
config.provider :apple,
  client_id: ENV["APPLE_CLIENT_ID"],       # the Services ID
  team_id: ENV["APPLE_TEAM_ID"],
  key_id: ENV["APPLE_KEY_ID"],
  private_key: ENV["APPLE_PRIVATE_KEY"]    # the contents of the .p8 file
```

| Option | Sent to Apple | Notes |
| --- | --- | --- |
| `scope` | yes | defaults to `email name`; `openid` is always added |
| `team_id`, `key_id`, `private_key` | no | sign the client secret, a five-minute JWT made for each request |

There is no `client_secret` to configure. The key must keep its line breaks;
one flattened to a single line with `\n` written out does not parse, and the
strategy raises when it is asked to leave for Apple.

## At Apple

In the developer account: an App ID with Sign in with Apple, a Services ID
(the `client_id`) with your domain and callback address, and a key with Sign
in with Apple enabled. Apple requires HTTPS and a real domain; `localhost`
is refused.

## The callback is a POST

Apple posts `code`, `state` and `user` to your callback from its own page.
The browser leaves the session cookie out of that request (`SameSite=Lax`),
so nothing can be checked there. Accept the `POST` and send it on to your
`GET` callback, which then works as for any other strategy:

```ruby
post "auth/apple/callback", to: "auth#apple"
get  "auth/apple/callback", to: "auth#callback", as: :auth_callback

skip_forgery_protection only: :apple

def apple
  redirect_to auth_callback_url(request.request_parameters.slice("code", "state", "user", "error")),
    status: :see_other
end
```

Skipping forgery protection is safe for that one action: it changes nothing,
and the state is still checked against the session on the `GET`.

## What comes back

| | |
| --- | --- |
| `auth.uid` | the `sub` claim: stable for this person across your team's apps |
| `auth.info.name` | first and last name from `user`, sent **only the first time** a person signs in. Store it then |
| `auth.info.email` | the `email` claim; a `privaterelay.appleid.com` address when the person hides theirs |
| `auth.info.email_verified` | what Apple says, read as a boolean or as `"true"` |
| `auth.info.image` | never; Apple has no picture |
| `auth.credentials` | `access_token`, `refresh_token`, `expires_at`. Apple has no API to call with them |
| `auth.raw` | every claim in the ID token, such as `is_private_email` |

A relay address matches no address your app already knows. Linking an
existing account by email will not find a person who hides theirs.

## Checks

The ID token is read from the token endpoint and checked for audience (your
Services ID), expiry, the nonce sent with this request, and issuer
(`https://appleid.apple.com`). A token that fails is an
`AnyAuth::Unauthorized`. The name in `user` is not signed, so treat it as
what the person typed.
