#!/usr/bin/env bash
set -Eeuo pipefail

export PATH="$HOME/.elixir-install/installs/otp/27.1.2/bin:$PATH"
export PATH="$HOME/.elixir-install/installs/elixir/1.17.2-otp-27/bin:$PATH"
export MIX_ENV=prod

APP_DIR="/opt/tigoo-app/server"
NODE_NAME="posserver@138.197.112.92"

cd "$APP_DIR"

# Load environment
if [[ -f .env-prod ]]; then
    set -a
    source .env-prod
    set +a
fi

if [[ -n "${PHX_HOST:-}" && -z "${SESSION_COOKIE_DOMAIN:-}" ]]; then
    export SESSION_COOKIE_DOMAIN=".${PHX_HOST}"
fi


# Authoritative sync with origin/main.
# WARNING: destroys local tracked changes and untracked files.
git fetch origin main
git reset --hard origin/main
git clean -fd

# Production dependencies and compilation
mix local.hex --force
mix local.rebar --force
mix deps.get --only prod
mix deps.compile
mix compile
mix assets.deploy

# Start distributed Elixir node
if [[ "${1:-}" == "norun" ]]; then
    echo "Just compiling and updating no run, bye ... "
    exit 0
fi

exec elixir \
    --name "$NODE_NAME" \
    --cookie "$ERLANG_COOKIE" \
    -S mix run --no-halt
