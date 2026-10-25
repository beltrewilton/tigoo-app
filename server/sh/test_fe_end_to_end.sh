#!/usr/bin/env bash
set -euo pipefail

# Usage: bash sh/test_fe_end_to_end.sh [http://ans.localhost:4000]
# Requires the updated server to be running and its tenant migration applied.
server_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$server_dir"
set -a
[ ! -f .env ] || . ./.env
set +a

for tool in curl mix jq; do
  command -v "$tool" >/dev/null || { echo "Required command missing: $tool" >&2; exit 1; }
done

export FE_CHECK_URL="${1:-http://ans.localhost:4000}"
FE_CHECK_URL="${FE_CHECK_URL%/}"
curl_options=()
authority="${FE_CHECK_URL#*://}"
authority="${authority%%/*}"
host="${authority%%:*}"
if [[ "$host" == localhost || "$host" == *.localhost ]]; then
  port=80
  [[ "$FE_CHECK_URL" != https://* ]] || port=443
  [[ "$authority" != *:* ]] || port="${authority##*:}"
  curl_options=(--resolve "${host}:${port}:127.0.0.1" --noproxy "$host")
fi
export FE_CHECK_DIRECTORY
FE_CHECK_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/tigoo-fe-check.XXXXXX")
trap 'rm -rf "$FE_CHECK_DIRECTORY"' EXIT

request() {
  local status
  status=$(curl "${curl_options[@]}" --silent --show-error \
    --dump-header "$FE_CHECK_DIRECTORY/headers" \
    --output "$FE_CHECK_DIRECTORY/response" \
    --write-out '%{http_code}' "$@")
  cat "$FE_CHECK_DIRECTORY/headers"
  cat "$FE_CHECK_DIRECTORY/response"
  printf '\n'
  if [ "$status" != 200 ]; then
    echo "Stopped: expected HTTP 200, received $status." >&2
    exit 1
  fi
}

printf '\n1. Request fresh XML seed\n'
request --header 'Accept: application/xml' \
  "$FE_CHECK_URL/fe/autenticacion/api/semilla"
cp "$FE_CHECK_DIRECTORY/response" "$FE_CHECK_DIRECTORY/semilla.xml"

printf '\n2. Read tenant RNC, prepare E31, and sign both XML files\n'
cat > "$FE_CHECK_DIRECTORY/prepare.exs" <<'ELIXIR'
import Ecto.Query
alias TigooServer.{Repo, Sign, Tenants}
alias TigooServer.Accounts.Company

# Use the existing build without starting a second HTTP listener.
endpoint = Application.get_env(:tigoo_server, TigooServerWeb.Endpoint, [])
Application.put_env(:tigoo_server, TigooServerWeb.Endpoint, Keyword.put(endpoint, :server, false))
{:ok, _} = Application.ensure_all_started(:tigoo_server)

host = System.fetch_env!("FE_CHECK_URL") |> URI.parse() |> Map.fetch!(:host)
{:tenant, tenant} = TigooServerWeb.Plugs.ResolveTenant.tenant_from_host(host)
true = Tenants.exists?(tenant)
prefix = Triplex.to_prefix(tenant)
%{rows: [[table_exists]]} = Repo.query!(
  "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'fe_received_ecfs')",
  [prefix])
unless table_exists do
  raise "Missing #{prefix}.fe_received_ecfs: apply tenant migration 20261025000000 before running this check."
end
[rnc] = Repo.all(from(c in Company, where: c.active == true,
  select: c.rnc, distinct: true, limit: 2), prefix: prefix)
true = is_binary(rnc) and Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, rnc)

directory = Path.join(Application.fetch_env!(:tigoo_server, :fe_receivers_directory), tenant)
{:ok, files} = File.ls(directory)
[filename] = Enum.filter(files, &(String.downcase(Path.extname(&1)) == ".p12"))
p12 = Path.join(directory, filename)
credentials = File.read!(Path.join(directory, "credentials.txt"))
[[password]] = Regex.scan(~r/^[\t ]*Password[\t ]*[:=][\t ]*([^\r\n]+)\r?$/mi,
  credentials, capture: :all_but_first)
password = password |> String.trim() |> String.trim("\"") |> String.trim("'")

output = System.fetch_env!("FE_CHECK_DIRECTORY")
now = DateTime.utc_now() |> DateTime.add(-4 * 3600, :second)
sequence = (:crypto.strong_rand_bytes(8) |> :binary.decode_unsigned() |> rem(9_999_999_999)) + 1
encf = "E31" <> String.pad_leading(Integer.to_string(sequence), 10, "0")
xml = File.read!("../fe/samples/101672919E310000000001.xml")
xml = Regex.replace(~r/<RNCComprador>[^<]*<\/RNCComprador>/, xml,
  "<RNCComprador>#{rnc}</RNCComprador>")
xml = Regex.replace(~r/<eNCF>[^<]*<\/eNCF>/, xml, "<eNCF>#{encf}</eNCF>")
xml = Regex.replace(~r/<FechaEmision>[^<]*<\/FechaEmision>/, xml,
  "<FechaEmision>#{Calendar.strftime(now, "%d-%m-%Y")}</FechaEmision>")
xml = Regex.replace(~r/<FechaHoraFirma>[^<]*<\/FechaHoraFirma>/, xml,
  "<FechaHoraFirma>#{Calendar.strftime(now, "%d-%m-%Y %H:%M:%S")}</FechaHoraFirma>")
{:ok, signed} = Sign.sign(xml, p12, password)
File.write!(Path.join(output, "signed-ecf.xml"), signed)
:ok = Sign.sign_file(Path.join(output, "semilla.xml"),
  Path.join(output, "signed-seed.xml"), p12, password)
IO.puts("Tenant: #{tenant}; receiver RNC from DB: #{rnc}; sample eNCF: #{encf}")
IO.puts("Seed and E31 signed successfully.")
ELIXIR
mix run --no-compile --no-start "$FE_CHECK_DIRECTORY/prepare.exs"

printf '\n3. Authenticate signed seed\n'
request --header 'Accept: application/json' \
  --form "xml=@${FE_CHECK_DIRECTORY}/signed-seed.xml;type=text/xml" \
  "$FE_CHECK_URL/fe/autenticacion/api/validacioncertificado"
token=$(jq -er '.token | select(type == "string" and length > 0)' "$FE_CHECK_DIRECTORY/response")

printf '\n4. Receive E31 — XML response (expected Estado 0)\n'
request --header 'Accept: application/xml' \
  --header "Authorization: Bearer $token" \
  --form "xml=@${FE_CHECK_DIRECTORY}/signed-ecf.xml;type=text/xml" \
  "$FE_CHECK_URL/fe/recepcion/api/ecf"
if [[ $(cat "$FE_CHECK_DIRECTORY/response") != *'<Estado>0</Estado>'* ]]; then
  echo 'Stopped: invoice was not accepted. Review the receipt above.' >&2
  exit 1
fi

printf '\n5. Resubmit E31 — JSON response (expected duplicate, code 3)\n'
request --header 'Accept: application/json' \
  --header "Authorization: Bearer $token" \
  --form "xml=@${FE_CHECK_DIRECTORY}/signed-ecf.xml;type=text/xml" \
  "$FE_CHECK_URL/fe/recepcion/api/ecf"
jq -e '.ARECF.DetalleAcusedeRecibo | .Estado == "1" and .CodigoMotivoNoRecibido == "3"' \
  "$FE_CHECK_DIRECTORY/response" >/dev/null

printf '\nPASS: authentication, XML reception, and JSON duplicate response completed.\n'
