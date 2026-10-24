# Tenant-aware API

Each SaaS tenant is a Triplex PostgreSQL schema. The public `users` table owns
the allowed tenant identifier; tenant data is never selected from a request
parameter.

Tenant-owned API routes use the `:tenant_api` pipeline. Send the opaque binary
session token as URL-safe Base64 in the request header:

```http
Authorization: Bearer <Base.url_encode64(token, padding: false)>
```

The pipeline resolves the token to its user, assigns `current_scope`, stores
`current_scope.user.tenant` in `TigooServer.TenantContext`, and rejects missing
or invalid credentials with `401`. Tenant contexts must read
`TenantContext.tenant!/0` and pass it as the Ecto `prefix:` or through the
tenant-aware SQL helper. Do not accept a tenant ID from HTTP params, JSON, or
the desktop client.

`TigooServer.Accounts.create_company_user/2` already provisions the tenant
schema with `Triplex.create_schema/3` and runs its tenant migrations before it
inserts the tenant's company and membership.

## IEx tenant commands

Start IEx from `server` with `iex -S mix`. Use a unique tenant name; creating
the same tenant twice is intentionally rejected.

```elixir
alias TigooServer.Accounts
alias TigooServer.{Repo, TenantContext}
alias TigooServer.Retaily.{Product, Sql}
import Ecto.Query

tenant = "demo_#{System.unique_integer([:positive])}"

{:ok, user} =
  Accounts.create_company_user(
    %{
      "name" => "Demo Cashier",
      "email" => "#{tenant}@example.test",
      "tenant" => tenant,
      "password" => "a-long-demo-password"
    },
    %{"company_name" => "Demo Store"}
  )

# Confirm the Triplex schema exists and obtain its PostgreSQL prefix.
Triplex.exists?(tenant)
prefix = Triplex.to_prefix(tenant)

# Create a desktop API token and the exact Authorization header value.
{:ok, session_token} = Accounts.create_user_token(%{"user_id" => user.id})
bearer_token = Accounts.encode_session_token(session_token)
authorization_header = "Bearer #{bearer_token}"

# Use tenant-scoped context functions in IEx.
TenantContext.put_tenant(user.tenant)
TenantContext.tenant!()
Sql.active_products_page(nil, limit: 10)

# Equivalent direct Ecto read; always supply the tenant prefix explicitly.
Repo.all(from(product in Product, order_by: [asc: product.id], limit: 10), prefix: prefix)
```

Use `authorization_header` as the `Authorization` header for `/api/products`.
