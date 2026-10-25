#!/usr/bin/env bash
set -euo pipefail

# Usage: bash sh/test_fe_validacioncertificado.sh [signed-seed.xml] [https://your-host]
file="${1:-signed-seed.xml}"
base_url="${2:-http://localhost:4000}"

curl --fail-with-body --include \
  --header 'Accept: application/json' \
  --form "xml=@${file};type=text/xml" \
  "${base_url%/}/fe/autenticacion/api/validacioncertificado"
