# Adversus

Fields only: there is no round trip. The person types an API login.

## Configure

```ruby
config.provider :adversus
```

## Fields

| Field | What it is |
| --- | --- |
| `username` | the API user's name |
| `password` | its password |

Both are required. Show them with a form as in
[the README](../../README.md#ask-for-the-fields), with `password_field` for the
password.

## Checking what was typed

`valid?` only checks that both are present. Call the Adversus API once with
them before saving, to learn whether the login works.

## What you store, and how it is presented

Store `strategy.attributes`, and send them to the API as HTTP basic auth. The
login does not expire, so `refresh` returns it unchanged.
