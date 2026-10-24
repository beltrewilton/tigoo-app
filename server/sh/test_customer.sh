#!/usr/bin/env bash
set -euo pipefail

server_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$server_dir"

MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
MIX_ENV=test mix run scripts/setup_sales_test_tenants.exs
MIX_ENV=test mix test test/tigoo_server_web/controllers/customer_controller_test.exs --trace "$@"
