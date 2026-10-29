#!/usr/bin/env bash
set -euo pipefail

# From any directory: bash /path/to/server/sh/sign_fe_declaracion_jurada.sh <tenant> [input.xml|directory] [output.xml]
# Elixir owns signing and tenant credential resolution. This launcher never compiles.
if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 <tenant> [input.xml|directory] [output.xml]" >&2
  exit 1
fi

server_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export FE_DECLARATION_TENANT="$1"
export FE_DECLARATION_INPUT="${2:-$server_dir/../fe/declaracion_jurada}"
export FE_DECLARATION_OUTPUT="${3:-}"
export FE_DECLARATION_CALLER_DIR="$PWD"
cd "$server_dir"
set -a
[ ! -f "${ENV_FILE:-.env}" ] || . "${ENV_FILE:-.env}"
set +a

mix run --no-compile --no-start -e '
{:ok, _} = Application.ensure_all_started(:public_key)
tenant = System.fetch_env!("FE_DECLARATION_TENANT")
caller_dir = System.fetch_env!("FE_DECLARATION_CALLER_DIR")
input = System.fetch_env!("FE_DECLARATION_INPUT") |> Path.expand(caller_dir)
input = if File.dir?(input) do
  case Path.wildcard(Path.join(input, "*.xml")) |> Enum.reject(&String.ends_with?(&1, ".signed.xml")) do
    [path] -> path
    _ -> raise "Expected exactly one unsigned XML; supply its explicit path"
  end
else
  input
end
output = case System.fetch_env!("FE_DECLARATION_OUTPUT") do
  "" -> Path.rootname(input) <> ".signed.xml"
  path -> Path.expand(path, caller_dir)
end
case TigooServer.Fe.Declaration.sign_file(tenant, input, output) do
  :ok -> IO.puts("Signed declaration saved to #{output}")
  {:error, reason} -> raise "Declaration signing failed: #{inspect(reason)}"
end
'
