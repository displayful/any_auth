# e-conomic

Fields only: there is no round trip. The person pastes two tokens from
e-conomic.

## Configure

```ruby
config.provider "e-conomic", strategy: :economic
```

## Fields

| Field | What it is |
| --- | --- |
| `agreement_token` | the agreement grant token, given when a company grants your app access |
| `app_token` | your app's secret token |

Both are required. Show them with a form as in
[the README](../../README.md#showing-the-form), and use `password_field`: they
are secrets.

## Checking what was typed

`valid?` only checks that both are present. To find out whether e-conomic
accepts them, call its API once before saving:

```ruby
strategy = AnyAuth.strategy("e-conomic", fields)
Faraday.get("https://restapi.e-conomic.com/self", nil,
  "X-AppSecretToken" => strategy.app_token, "X-AgreementGrantToken" => strategy.agreement_token)
```

## What you store, and how it is presented

Store `strategy.attributes`, and send them as the two headers above on every
request. The tokens do not expire, so `refresh` returns them unchanged.
