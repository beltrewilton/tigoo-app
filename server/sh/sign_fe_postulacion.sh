#!/usr/bin/env bash
set -euo pipefail

# Run from server: bash sh/sign_fe_postulacion.sh ans ../fe/202610253240465.xml [output.xml]
if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: bash sh/sign_fe_postulacion.sh <tenant> <input.xml> [output.xml]" >&2
  exit 1
fi

server_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$server_dir"
set -a
[ ! -f "${ENV_FILE:-.env}" ] || . "${ENV_FILE:-.env}"
set +a

export FE_APPLICATION_TENANT="$1"
export FE_APPLICATION_INPUT="$2"
export FE_APPLICATION_OUTPUT="${3:-${2%.xml}.signed.xml}"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/tigoo-postulacion.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

cat > "$work_dir/sign.exs" <<'ELIXIR'
alias TigooServer.{Sign, Tenants}
{:ok, _} = Application.ensure_all_started(:public_key)

tenant = System.fetch_env!("FE_APPLICATION_TENANT")
unless Tenants.valid_identifier?(tenant), do: raise("Invalid tenant identifier")
directory = Path.join(Application.fetch_env!(:tigoo_server, :fe_receivers_directory), tenant)

files = case File.ls(directory) do
  {:ok, files} -> files
  {:error, reason} -> raise "Cannot read #{directory}: #{:file.format_error(reason)}"
end

p12 = case Enum.filter(files, &(String.downcase(Path.extname(&1)) == ".p12")) do
  [filename] -> Path.join(directory, filename)
  _ -> raise "Expected exactly one .p12 in #{directory}"
end

credentials = File.read!(Path.join(directory, "credentials.txt"))
password = case Regex.scan(~r/^[\t ]*Password[\t ]*[:=][\t ]*([^\r\n]+)\r?$/mi,
  credentials, capture: :all_but_first) do
  [[value]] -> value |> String.trim() |> String.trim("\"") |> String.trim("'")
  _ -> raise "Expected one Password field in credentials.txt"
end

input = System.fetch_env!("FE_APPLICATION_INPUT") |> Path.expand()
output = System.fetch_env!("FE_APPLICATION_OUTPUT") |> Path.expand()
if input == output or File.exists?(output), do: raise("Output must be a new file; input is preserved")
%{size: size} = File.stat!(input)
if size > 5_000_000, do: raise("XML exceeds 5 MB")
xml = File.read!(input)

case Saxy.SimpleForm.parse_string(xml, expand_entity: {Sign, :reject_entity, []}) do
  {:ok, {"Postulacion", _, _}} -> :ok
  _ -> raise "Expected a DGII XML document with root Postulacion"
end

case Sign.sign(xml, p12, password) do
  {:ok, signed} ->
    File.write!(output, signed, [:exclusive])
    IO.puts("Signed application saved to #{output}")
    IO.puts("Upload this file under Envío de archivo de postulación firmado. Do not edit it after signing.")
  {:error, reason} -> raise "Application signing failed: #{reason}"
end
ELIXIR

mix run --no-compile --no-start "$work_dir/sign.exs"
