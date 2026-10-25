#!/usr/bin/env bash
set -euo pipefail

# Usage: bash sh/test_fe_semilla.sh [https://your-host] [output.xml]
base_url="${1:-http://localhost:4000}"
output="${2:-semilla.xml}"
url="${base_url%/}/fe/autenticacion/api/semilla"

curl --fail --silent --show-error --header 'Accept: application/xml' \
  --output "$output" "$url"
printf 'Seed saved to %s\n' "$output"
