#!/usr/bin/env bash
set -euo pipefail

server_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$server_dir"

if [[ $# -gt 2 ]]; then
  echo "Usage: $0 [report_file] [calls_per_user]" >&2
  exit 1
fi

if [[ ! -f "$server_dir/.env" ]]; then
  echo "Missing $server_dir/.env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$server_dir/.env"
set +a

: "${DB_USER:?Set DB_USER in server/.env}"
: "${DB_PASS:?Set DB_PASS in server/.env}"
: "${DB_NAME:?Set DB_NAME in server/.env}"

if [[ $# -ge 1 ]]; then
  report_file=$1
else
  report_file="/tmp/ans_rotation_report_$(date +%Y%m%d_%H%M%S)_$$.txt"
fi

if [[ -e "$report_file" ]]; then
  echo "Report already exists: $report_file. Choose a new path." >&2
  exit 1
fi

calls_per_user=${2:-500}
if [[ ! "$calls_per_user" =~ ^[1-9][0-9]*$ ]]; then
  echo "Calls per user must be a positive integer." >&2
  exit 1
fi

echo "Running sequence simulation for tenant ans..."
echo "Report: $report_file"
exec mix run scripts/simulate_sequence_rotation.ex "$report_file" "$calls_per_user"
