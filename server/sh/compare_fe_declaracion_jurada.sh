#!/usr/bin/env bash
set -euo pipefail

# Builds the Elixir modules, signs with the tenant identity, then compares bytes.
# Run this script yourself; it never uploads to DGII or starts the application.
if [[ $# -lt 1 || $# -gt 4 ]]; then
  echo "Usage: $0 <tenant> [input.xml] [reference.signed.xml] [output.signed.xml]" >&2
  exit 1
fi

server_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
repo_dir=$(cd -- "$server_dir/.." && pwd)
tenant=$1
input=${2:-$repo_dir/fe/declaracion_jurada/202610284618403.xml}
reference=${3:-$repo_dir/fe/declaracion_jurada/202610284618403.compact.signed.xml}
output=${4:-$repo_dir/fe/declaracion_jurada/202610284618403.elixir.signed.xml}

for file in "$input" "$reference"; do
  if [[ ! -f "$file" ]]; then
    echo "File not found: $file" >&2
    exit 1
  fi
done
if [[ -e "$output" || -L "$output" ]]; then
  echo "Output already exists; choose a new output path: $output" >&2
  exit 1
fi

echo "Building Elixir modules (no tests or formatting)..."
(
  cd "$server_dir"
  set -a
  [ ! -f "${ENV_FILE:-.env}" ] || . "${ENV_FILE:-.env}"
  set +a
  mix compile
)

bash "$server_dir/sh/sign_fe_declaracion_jurada.sh" "$tenant" "$input" "$output"

if cmp -s "$reference" "$output"; then
  echo "IDENTICAL: generated XML matches the reference byte-for-byte."
else
  comparison_status=$?
  if [[ "$comparison_status" -ne 1 ]]; then
    echo "Unable to compare files." >&2
    exit "$comparison_status"
  fi
  echo "DIFFERENT: generated XML does not match the reference byte-for-byte." >&2
  echo "Reference: $reference" >&2
  echo "Generated: $output" >&2
  echo "Both files were preserved. A byte difference alone does not establish signature invalidity." >&2
  exit 1
fi
