# Tigoo POS

Web-based point-of-sale application built with Elixir, Phoenix LiveView, and PostgreSQL. Includes sales and payments, customers, inventory, purchase orders, reports, and tenant accounts.

- `server/` — Elixir/Phoenix APIs, LiveView screens, authentication, and schema-based tenancy via Triplex.
- `ui/` — vendored UI components; see [UI asset instructions](ui/README.md).

## Local development

Requires Elixir 1.15+, Erlang/OTP, and PostgreSQL.

Create the PostgreSQL database separately, then configure the server:

```sh
cd server
cp .env.example .env
# Edit .env with your database credentials and configuration.
set -a
. ./.env
set +a
mix setup
./sh/migrate.sh .env
./sh/run_local.sh
```

`mix setup` installs dependencies and builds assets; it does not create the database. The migration command above applies public migrations. To create or migrate a tenant schema, run `./sh/migrate.sh .env <tenant_schema>`.

The server defaults to `http://localhost:4000`; check `/api/health` for health status. Tenant POS screens use `http://<tenant>.localhost:4000/pos`. Configure `GOOGLE_CLIENT`, `GOOGLE_KEY`, and the OAuth callback for Google sign-in; `/admin/login` uses `ADMIN_USER` and `ADMIN_PASWORD` (the spelling used by the application).
