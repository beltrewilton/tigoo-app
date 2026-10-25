#!/usr/bin/env bash
set -euo pipefail

# Usage: FE_TOKEN='...' bash sh/test_fe_recepcion.sh [signed-ecf.xml] [http://ans.localhost:4000] [xml|json]
file="${1:-signed-ecf.xml}"
base_url="${2:-http://ans.localhost:4000}"
format="${3:-xml}"
: "${FE_TOKEN:?Set FE_TOKEN to the token returned by validacioncertificado}"

curl --fail-with-body --include \
  --header "Accept: application/${format}" \
  --header "Authorization: Bearer ${FE_TOKEN}" \
  --form "xml=@${file};type=text/xml" \
  "${base_url%/}/fe/recepcion/api/ecf"
