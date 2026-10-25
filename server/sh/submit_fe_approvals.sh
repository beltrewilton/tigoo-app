#!/usr/bin/env bash
set -euo pipefail
umask 077

# Sends real ACECF requests to DGII. No compilation, tests or formatting.
server_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export TIGOO_FE_REPO_ROOT
TIGOO_FE_REPO_ROOT=$(cd -- "$server_dir/.." && pwd)
export TIGOO_FE_CALLER_DIR="$PWD"

if ! command -v mix >/dev/null 2>&1; then
  echo "Elixir/Mix is required on PATH." >&2
  exit 2
fi

cd "$server_dir"
exec mix run --no-compile --no-deps-check --no-start scripts/commercial_approval.exs submit "$@"
