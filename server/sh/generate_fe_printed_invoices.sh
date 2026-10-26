#!/usr/bin/env bash
set -euo pipefail
umask 077
server_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export TIGOO_FE_REPO_ROOT
TIGOO_FE_REPO_ROOT=$(cd -- "$server_dir/.." && pwd)
export TIGOO_FE_CALLER_DIR="$PWD"
cd "$server_dir"
exec mix run --no-compile --no-deps-check --no-start scripts/generate_fe_printed_invoices.exs "$@"
