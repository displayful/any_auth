# SAML

Signs people in through their company's identity provider (Okta, Entra ID,
Google Workspace, OneLogin…) over SAML 2.0. Built on
[ruby-saml](https://github.com/SAML-Toolkits/ruby-saml), which checks the XML
signature.

If the customer's IdP also speaks OpenID Connect, prefer that: it has none of
the trade-offs below.

## Install

```ruby
# Gemfile
gem "ruby-saml", ">= 1.18.1"
```

```ruby
# config/initializers/any_auth.rb
require "any_auth/strategies/saml"

AnyAuth.configure do |config|
  config.provider :saml, sp_entity_id: "https://example.com/saml"
end
```

The strategy is not loaded by default, and ruby-saml is not a dependency of
AnyAuth. Loading the strategy without ruby-saml in your bundle, or with a
version before 1.18.1 (which have published signature bypasses), raises a
`LoadError` saying so. Keep ruby-saml up to date: its security is the
strategy's.

## Configure per customer

Each customer runs their own IdP, so its settings come from your database, in
the [setup step](../../README.md#configuring-each-sign-in-omniauths-setup-phase):

```ruby
AnyAuth.strategy(:saml,
  idp_sso_service_url: account.idp_sso_url,
  idp_cert: account.idp_certificate,
  idp_entity_id: account.idp_entity_id,
  assertion_consumer_service_url: auth_callback_url(:saml))
```

| Option | What it is |
| --- | --- |
| `idp_sso_service_url` | where the IdP signs people in (HTTP-Redirect binding) |
| `idp_cert` | the IdP's signing certificate, PEM |
| `idp_entity_id` | the IdP's entity ID; the response's issuer must match |
| `sp_entity_id` | your entity ID; the response's audience must match |
| `assertion_consumer_service_url` | your callback; the response must be addressed to it |
| `name_identifier_format` | the NameID format to ask for, such as `urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress` |

The first five are required: a strategy missing any of them raises
`ArgumentError` naming it, because ruby-saml quietly skips the check a missing
setting would make. Set `assertion_consumer_service_url` when building the
strategy for the callback too: the session is usually gone there (see below).
`metadata` needs only `sp_entity_id` and `assertion_consumer_service_url`, so
you can hand it to a customer before their IdP is set up.

## At the IdP

The customer creates a SAML app with your entity ID and callback, or loads
your metadata. Serve it from a route of your own:

```ruby
def show
  render xml: AnyAuth.strategy(:saml, assertion_consumer_service_url: auth_callback_url(:saml)).metadata
end
```

## The callback is a POST

The IdP posts `SAMLResponse` to your callback from its own page. Accept the
`POST` and skip forgery protection for that action; the response is checked
by its signature instead:

```ruby
# config/routes.rb, inside the auth scope
resource :callback, only: %i[ show create ]
```

```ruby
class Auth::CallbacksController < Auth::BaseController
  skip_forgery_protection only: :create

  def create
    # the same as show: authenticate_with_provider reads the POST body
  end
end
```

## What comes back

| | |
| --- | --- |
| `auth.uid` | `<idp_entity_id>:<NameID>` |
| `auth.info.email` | the `email` attribute, or `mail` |
| `auth.info.name` | the `name` attribute |
| `auth.info.email_verified` | always false: the customer runs the IdP and decides what it asserts |
| `auth.credentials` | empty |
| `auth.raw` | every attribute, each a list of values |

`uid` names the IdP as well as the person. Every customer's IdP is configured
under the same provider, and a customer controls what their IdP asserts, so a
bare NameID such as `mette@acme.test` could be claimed by another customer's
IdP. Keyed on `provider` and `uid`, each customer's people stay their own.

Linking a SAML sign-in to an existing account by email is your decision, per
customer: trust only an IdP whose domain the customer has proven they own.

## Checks

ruby-saml checks the signature against `idp_cert`, the issuer, the audience,
the destination and recipient, and the timestamps (with five seconds of
clock drift). Two of its checks are stricter than its defaults: the response
must name your entity ID as its audience, and must name a person (a NameID).
An invalid response is an `AnyAuth::InvalidCallback`, a refusal from the IdP an `AnyAuth::AccessDenied`; a callback without one is
an `AnyAuth::InvalidCallback`.

## The trade-off

This is the trade-off omniauth-saml makes too.

The IdP's `POST` comes from another site, and Rails' session cookie is
`SameSite=Lax`, so the browser does not send it. The response therefore cannot
be tied to a sign-in this browser started: `InResponseTo` is checked only when
the session happens to be there. As a result:

- A response is accepted on its signature alone, until it expires (usually a
  few minutes). A captured response can be replayed in that window; record
  each assertion's ID (`auth.raw` does not include it) if that matters to you.
- Sign-in started from the IdP's own dashboard (IdP-initiated) is accepted.

Single logout is not supported.
