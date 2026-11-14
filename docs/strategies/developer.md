# Developer

Signs in as whoever you say you are. It exists so that sign-in can be used on
a development machine with no vendor, no client id and no network.

**It checks nothing. Never register it outside development.**

## Configure

```ruby
config.provider :developer if Rails.env.development?
```

Registering it behind that condition is the whole safeguard: where it is not
registered, `AnyAuth.strategy(:developer)` raises, and your route for it should
not exist.

## Field

| Field | What it is |
| --- | --- |
| `email` | the address of the person to sign in as |

## Using it

There is no `request_phase`. Give it an email and call `callback_phase` with
no arguments:

```ruby
developer = AnyAuth.strategy(:developer, email: params[:email])
auth = developer.callback_phase
```

A controller that serves both kinds can branch on that:

```ruby
if strategy.respond_to?(:request_phase)
  redirect_to_provider strategy, redirect_uri: callback_url
else
  strategy.email = params[:email]
  sign_in_as strategy.callback_phase
end
```

## What comes back

| | |
| --- | --- |
| `auth.provider` | `"developer"` |
| `auth.uid` | the email, trimmed and in lower case |
| `auth.info.email` | the same address |
| `auth.info.email_verified` | always true |
| `auth.credentials` | empty |

Because `email_verified` is always true, an app that links accounts by
verified email will sign you in as any existing person. That is the point,
and the reason it must stay out of production.

A missing email is an `AnyAuth::InvalidCallback`.
