# Shopify

OAuth 2 for one shop's Admin API. It is the strategy that asks for a field
first: every shop has its own sign-in address.

## Configure

```ruby
config.provider :shopify, client_id: "…", client_secret: "…", scope: "read_orders"

AnyAuth.strategy(:shopify, shop: "mystore")
```

## The field: `shop`

Whatever the person types is turned into the shop's `myshopify.com` address:

| Typed | Becomes |
| --- | --- |
| `mystore` | `mystore.myshopify.com` |
| `MyStore.myshopify.com` | `mystore.myshopify.com` |
| `https://mystore.myshopify.com/admin` | `mystore.myshopify.com` |
| `https://admin.shopify.com/store/mystore/orders` | `mystore.myshopify.com` |
| `evil.test/x` | `evil.test`, which is invalid |

`valid?` accepts only `<name>.myshopify.com`. It does not ask Shopify whether
the shop exists; a shop that does not exist answers 404 on its sign-in address.

See [the README](../../README.md#vendors-that-ask-for-something-first) for the
form and the controller: the shop has to travel with the request, because the
callback needs the same strategy.

## At Shopify

Create an app in the Dev Dashboard, add your callback address as a redirect
URL, and list the scopes you ask for.

## What is different

| Step | What Shopify adds |
| --- | --- |
| `verify` | the callback must name the shop the person left for, and carry Shopify's HMAC of its parameters, made with your client secret. Otherwise it is an `AnyAuth::InvalidCallback` |
| `exchange` | asks for an expiring offline token (`expiring: 1`), so a refresh token comes back |
| `authorization` | `{ "X-Shopify-Access-Token" => "…" }`, not a bearer header |

Shopify replaces the refresh token every time it is used. Two processes
refreshing at once will leave one of them with a dead token, so check
`strategy.expired?(credentials)`, take a lock or reload, and only then call
`fresh`.

## What comes back

| | |
| --- | --- |
| `auth.uid`, `auth.info` | nil |
| `auth.credentials` | `access_token`, `refresh_token`, `expires_at` |

Store `strategy.attributes.merge(auth.credentials)`: the shop and the tokens
together. To name the shop, ask the Admin API for `shop { id name }`.
