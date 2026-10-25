# DGII Elixir client

`TigooServer.Fe.Client` implements outbound DGII authentication, ECF reception,
RFCE reception, and track-ID consultation. It reuses `TigooServer.Sign`, Req,
the generation XML helpers and a shared `TigooServer.Fe.Credentials` reader.
`TigooServer.Fe.Submission` sends a generated manifest sequentially and records
its progress. No controllers, database tables, queues or schedulers are added.

## Run

The new/changed modules must be built through your normal project workflow first.
No compilation, tests, formatting, generator execution, authentication or document
submission were performed while implementing this change. The runner uses
`mix run --no-compile --no-deps-check --no-start` and starts only HTTP/crypto
dependencies, not Phoenix/Repo. It does not generate or re-sign invoices.

From the repository root, when the modules and generated batch are available:

```sh
bash server/sh/submit_fe_certification.sh \
  --batch fe/data-test/generated/131362702-25102026004903
```

**Running this command performs real DGII requests.** Defaults select certification
(`certecf`), issuer `131362702`, the signing identity under `p12_companies/ans/`,
and its `credentials.txt`. No password is passed on the command line. Explicit
`--p12`, `--credentials`, `--issuer-rnc`, and `--environment` support future use.
Allowed environments are `certecf`, `testecf`, and `ecf` (production).

Default output is `<batch>/submission-certecf.json`, independent of the generation
manifest. `--report PATH` selects another journal. Keep the same journal when
resuming; a different journal represents a new submission run and does not know
what another run sent. Relative paths resolve from your original working directory.

```sh
# Resume: accepted entries are skipped; stored track IDs are queried, not reposted.
bash server/sh/submit_fe_certification.sh --batch /absolute/path/batch

# Query one existing track ID; no invoice/RFCE upload.
bash server/sh/submit_fe_certification.sh --track-id YOUR_TRACK_ID
```

Polling defaults to 20 queries per ECF with a 1000 ms interval. Use
`--poll-attempts` and `--poll-interval` to change these limits. A pending result
stops the run; the same command can resume its consultation later. `--help`
lists receive timeout, schema directory and native executable overrides.

For the supplied manifest, the runner sends **21 full ECFs and four RFCEs** in
the dependency order. It does not send the four complete type-32 documents below
DOP 250,000 to normal reception. Their paths are listed in `portal_uploads` for
the certification portal step following acceptance of the summaries.

## Reusable API

```elixir
alias TigooServer.Fe.{Client, Submission}

client = Client.new(
  environment: "certecf",
  issuer_rnc: "131362702",
  p12_path: "/absolute/path/identity.p12",
  credentials_file: "/absolute/path/credentials.txt"
)

Submission.run("/absolute/path/generated-batch", client)
# {:ok, report} | {:error, %Client.Error{}, report_or_nil}
```

Lower-level operations can be used independently:

```elixir
{:ok, client} = Client.authenticate(client)
{:ok, receipt, client} = Client.send_ecf(client, "/path/131362702E310000000001.xml")
{:ok, result, client} = Client.result(client, receipt["trackId"])
Client.status(result) # :accepted | :accepted_conditional | :rejected | :pending | :not_found | :unknown

{:ok, summary_result, client} = Client.send_rfce(client, "/path/131362702E320000000011.xml")
Client.status(summary_result, :rfce)
```

All document/result calls return `{:ok, original_response_map, updated_client}`
or `{:error, %Client.Error{}}`. Keep the returned client to reuse token refreshes.
They also authenticate automatically when necessary. `Client.new/1` raises for
invalid local configuration and makes no HTTP requests. `password: password` can
replace `credentials_file` for in-memory callers. Client inspection redacts the
password and token. Neither is persisted in submission reports.

Direct upload helpers check the file size, root, issuer, eNCF/type, filename,
signature structure, authentication signer and the type-32 threshold. They send
the original bytes. The batch additionally checks generation-manifest hashes,
document metadata, the full ECF/RFCE security-code link and XSDs before HTTP.
It relies on the generated manifest's hash-pinned signed artifacts for the earlier
cryptographic verification; it does not repeat generation's trusted-chain check.
Arbitrary files should first go through the existing generation/validation flow.

The individual WILTON BELTRE certificate is used for the explicitly configured
EVOFIT issuer RNC; no company RNC is inferred from its certificate subject. The
upload signer must match the certificate used to sign the DGII authentication seed.

## Requests and responses

The current certification OpenAPI definitions were read from the four supplied
Swagger pages:

| Service | Request | Response handling |
|---|---|---|
| [Authentication](https://ecf.dgii.gov.do/CerteCF/Autenticacion/help/index.html) | GET `/api/Autenticacion/Semilla`; sign XML; POST `/api/Autenticacion/ValidarSemilla` | Keep `token`, `expira`, `expedido` in memory; refresh before expiry |
| [ECF reception](https://ecf.dgii.gov.do/CerteCF/Recepcion/help/index.html) | POST `/api/FacturasElectronicas` | Record `trackId`, `error`, `mensaje`; a track ID is not fiscal acceptance |
| [Result consultation](https://ecf.dgii.gov.do/CerteCF/ConsultaResultado/help/index.html) | GET `/api/Consultas/Estado?TrackId=...` | Preserve `codigo`, `estado`, `mensajes`, `encf`, `rnc`, `secuenciaUtilizada`, `fechaRecepcion` |
| [RFCE reception](https://fc.dgii.gov.do/certecf/recepcionfc/help/index.html) | POST `/api/recepcion/ecf` | Interpret the direct status response; preserve messages and `secuenciaUtilizada` |

All uploads use multipart field `xml`, the original filename and `text/xml`.
Authenticated requests use Bearer authorization and ask for JSON. The seed request
asks for XML. This is DGII's `ValidarSemilla` flow, separate from the local
issuer/receiver `validacioncertificado` convention. Local login tokens and ARECF
acknowledgements are not used to authenticate with DGII.

The live result schema declares `codigo` as a string, while the technical PDF
also shows integer examples; both are handled. Result consultation codes 1/4
are accepted/conditionally accepted, 2 rejected, 3 processing and 0 not found.
RFCE's OpenAPI enum does not describe every numeric value, so the runner uses its
explicit `estado` label and stops on an unknown status rather than guessing.
Original response fields, including nulls, are retained unchanged in the journal.

## Journal and retry behavior

The journal stores environment, issuer, manifest hash, filenames, checksums,
upload attempts, upload responses, track IDs, latest consultation responses,
fiscal states and errors. The runner saves `sending` **before** a document POST
and saves each response before moving on. It waits for accepted/conditionally
accepted ECF results before sending subsequent documents. References within the
batch follow the manifest order; references outside it require prior acceptance
to be verified by the operator.

Req retries and redirects are disabled. A 401, transport failure, server error,
missing track ID or interrupted POST never triggers an automatic fiscal repost.
Authentication/local-validation failures before a fiscal POST can be retried;
stored track IDs resume GET consultation. Rejected and unknown entries stop the
run. `secuenciaUtilizada: false` is recorded, not treated as permission to resend.
RFCE has no consultation endpoint among the four provided services: a nonfinal
RFCE response requires reconciliation through DGII before another upload.

If a process dies after DGII receives an upload but before a track ID is saved,
the journal remains `sending`. Reconcile that eNCF with DGII before deciding how
to continue. A journal write failure also requires reviewing the last persisted
entry. Do not delete the journal or choose a new report simply to bypass this
state. A `.lock` directory prevents simultaneous runs using the same journal;
after abrupt termination, remove a stale lock only after checking no process is
still using it.
