# Developer

Signs in as whoever you say you are. It exists so that sign-in can be used on
a development machine with no vendor, no client id and no network.

**It checks nothing. Never register it outside development.**

## Configure

```ruby
if Rails.env.development?
  require "any_auth/strategies/developer"
  config.provider :developer
end
```

The gem does not load it by itself. Where it is not required and registered,
`AnyAuth.strategy(:developer)` raises a `KeyError`, and your route for it
should not exist.

## Field

| Field | What it is |
| --- | --- |
| `email` | the address of the person to sign in as |

## Using it

It goes through the same two calls as every other strategy, so a controller
needs no special case. Ask for the email with a form for the strategy, as for
[any strategy with fields](../../README.md#fields):

```ruby
def create
  developer = AnyAuth.strategy(:developer, params.expect(strategy: [:email]))

  if developer.valid?
    redirect_to_any_auth developer, redirect_uri: callback_url
  else
    render :new, status: :unprocessable_content
  end
end

def callback
  auth = authenticate_with_any_auth(AnyAuth.strategy(:developer))
end
```

The person is sent straight to your own callback. The email is remembered
with the sign-in, not put in the address, and the callback still has to belong
to a sign-in started in this browser, as with any vendor. A blank email is
invalid, so the form comes back with the error.

## What comes back

| | |
| --- | --- |
| `auth.provider` | `"developer"` |
| `auth.uid` | the email, trimmed and in lower case |
| `auth.info.email` | the same address |
| `auth.info.email_verified` | always true |
| `auth.credentials` | empty |
| `auth.raw` | empty |

Because `email_verified` is always true, an app that links accounts by
verified email will sign you in as any existing person. That is the point,
and the reason it must stay out of production.

A missing email, or a callback nobody started, is an `AnyAuth::InvalidCallback`.
