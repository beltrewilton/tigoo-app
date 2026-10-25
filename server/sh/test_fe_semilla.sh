#!/usr/bin/env bash
set -euo pipefail

# Usage: bash sh/test_fe_semilla.sh [https://your-host]
base_url="${1:-http://localhost:4000}"
url="${base_url%/}/fe/autenticacion/api/semilla"

curl --fail-with-body --include --header 'Accept: application/xml' "$url"

curl --fail-with-body --include --header 'Accept: application/json' "$url"
