# e-CF reception

`POST /fe/recepcion/api/ecf` accepts a signed e-CF in the multipart field `xml`,
up to 5,000,000 bytes. `/fe/recepción/api/ecf` and mixed-case URL variants resolve
to the same endpoint. XML element names remain case sensitive, following the XSD.

Send `Authorization: Bearer <token>` using the token returned by
`/fe/autenticacion/api/validacioncertificado`. The invoice must be signed by the
same certificate that authenticated. Certificates are verified using the existing
configured CA trust chain; certificates supplied in a request never become trust anchors.

The hostname selects the tenant (`ans.localhost:4000` selects `ans`). The tenant's
receiver RNC comes from the active company in that tenant's database schema.
`RNCComprador` only checks whether the invoice is addressed to that receiver;
it never selects a tenant.

## Receiver setup

Apply the new tenant migration using your existing deployment migration workflow
before sending invoices. No migrations have been run as part of this change.
The table `fe_received_ecfs` stores the original signed invoice, signed receipt,
signing certificate fingerprint and timestamps, separately in each tenant schema.
The unique `(issuer_rnc, encf)` index handles duplicates, including concurrent requests.

Place each receiver's signing files in the project's `p12_companies/{tenant}` directory:

```text
p12_companies/
  ans/
    22813977_identity.p12
    credentials.txt
```

The certificate filename may vary; each tenant directory must contain exactly one
`.p12` file. `credentials.txt` must contain one `Password: ...` or `Password=...`
line; surrounding single or double quotes around the password are removed.
Files are read when receiving an invoice. The receiver RNC is the single distinct
RNC among active company records in the hostname's tenant schema. Missing or
ambiguous company RNCs, certificates or password fields return `503`.

The directory is configured as `:tigoo_server, :fe_receivers_directory` in
`config/runtime.exs`, relative to the project root. Provision this directory
on each deployment host; it is not bundled into releases or committed to Git.
Restrict access to the application OS user. Existing
`FE_XMLSEC_PATH`, `FE_OPENSSL_PATH` and CA settings are also required.
Missing configuration, signing failures or database failures return `503`,
without claiming receipt.

## Responses

`Accept: application/xml` (also the default) returns the signed `ARECF` document.
`Accept: application/json` returns `ARECF.DetalleAcusedeRecibo` plus `xml`, containing
the complete signed XML string. Preserve that XML string to verify its signature;
the JSON representation itself is not signed. Receipts use the XSD's field order,
with `FechaHoraAcuseRecibo` in `dd-MM-yyyy HH:mm:ss`, GMT-4.

An interpretable invoice receives HTTP `200` with a signed acknowledgement:

| Estado | CodigoMotivoNoRecibido | Meaning |
| --- | --- | --- |
| 0 | omitted | Received and stored |
| 1 | 1 | Invalid XSD specification or unsupported document type |
| 1 | 2 | Invalid signature or certificate differs from the bearer token |
| 1 | 3 | Duplicate issuer RNC and eNCF in this tenant |
| 1 | 4 | Buyer RNC does not match this receiver |

Missing/invalid/expired tokens return `401` with `WWW-Authenticate: Bearer`;
unknown tenant hosts return `404`; unreadable invoices or missing invoice identifiers
return `400`; files over the limit return `413`. These handled errors support XML
and JSON as well. Infrastructure request-size/negotiation errors follow Phoenix's
normal error handling.

Schemas are bundled under `priv/fe/xsd` from `../fe/xsd`.
The bundled E31 copy corrects a leading space in the downloaded schema's
`IndicadorServicioTodoIncluidoType` declaration, which xmerl otherwise treats as
an undeclared reference. The downloaded original is preserved.
Bundled RNC patterns also group the alternatives as `([0-9]{11}|[0-9]{9})`
to avoid xmerl's anchoring issue with ungrouped alternatives. This preserves
the same nine-or-eleven-digit constraint; downloaded schemas remain unchanged.
The declared `TipoeCF` selects the matching schema (31, 32, 33, 34, 41, 43, 44, 45, 46 or 47); the eNCF
must agree with that type. Documents must contain emitter and buyer RNCs.
Validation covers XSD structure/data types, receiver identity, certificate trust,
RSA-SHA256 signature and duplicates. An ARECF is an acknowledgement of receipt,
not commercial approval or DGII fiscal certification. This endpoint does not
implement all cross-field fiscal calculations or issuer-delegation checks with DGII.

## Quick end-to-end check

With the updated server running and tenant migration applied, run from `server`:

```sh
bash sh/test_fe_end_to_end.sh http://ans.localhost:4000
```

Requires `curl`, `mix`, and `jq`, an existing build, and the same database/environment
as the running server. The script loads `server/.env` and does not compile the project.
For `localhost` and `*.localhost`, curl connects to `127.0.0.1` using `--resolve`,
preserving the tenant hostname without requiring DNS or `/etc/hosts` changes.
It prints the HTTP status, headers and body for the seed, authentication, XML
reception and JSON duplicate response, then reports `PASS` or stops on failure.

It reads the receiver RNC from the tenant's active company records and puts it in
`RNCComprador` in a temporary copy of the E31 sample. It updates the dates and
generates a random sample eNCF so repeated runs can receive a new invoice. For this
local check, the tenant's `.p12` simulates the transmitter as well as signing the
receiver's acknowledgement. The sample's emitter identity remains illustrative.

Temporary files are deleted on exit; each successful run stores one invoice and
receipt in the tenant database. Printed authentication responses contain a live,
short-lived bearer token. The original sample is unchanged. The endpoint itself
compares the submitted buyer RNC against the database; it never rewrites invoices.

## E31 sample and manual submission

`../fe/samples/101672919E310000000001.xml` is an unsigned illustrative E31:
two services at 100.00, taxable base 200.00, 18% ITBIS 36.00, total 236.00.
The filename uses the full 13-character eNCF required by the XSD.
Replace issuer/buyer identities, company names, dates and sequence with your actual
data before signing. The buyer must match the configured receiver RNC.
The unsigned template intentionally has no placeholder signature; `TigooServer.Sign`
adds the mandatory XMLDSig element.

From IEx started in `server`, with the transmitter's password loaded in
`FE_TRANSMITTER_P12_PASSWORD`:

```elixir
TigooServer.Sign.sign_file(
  "../fe/samples/101672919E310000000001.xml",
  "signed-ecf.xml",
  "../fe/22813977_identity.p12",
  System.fetch_env!("FE_TRANSMITTER_P12_PASSWORD")
)
```

Authenticate using that same transmitter certificate, then submit the resulting
file using the returned token:

```sh
FE_TOKEN='token from validacioncertificado' bash sh/test_fe_recepcion.sh signed-ecf.xml http://ans.localhost:4000 xml
FE_TOKEN='token from validacioncertificado' bash sh/test_fe_recepcion.sh signed-ecf.xml http://ans.localhost:4000 json
```

The second submission intentionally receives the duplicate receipt if the first
was accepted. Never format or change the XML after signing it.

References: `Descripcion Tecnica Emisores Electronicos.pdf`, pages 10–11;
`Formato Comprobante Fiscal Electrónico (e-CF) V1.0.pdf`; the provided e-CF and
ARECF XSDs; [DGII receiver API documentation](https://ecf.dgii.gov.do/Testecf/EmisorReceptor/help/index.html).
