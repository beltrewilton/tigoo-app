# Commercial approval generation and DGII submission

The supplied workbook `fe/131362702-25102026175246.xlsx` contains **11 rows** on
its first and only sheet, **`ACEECF_Generadas`**. It describes commercial
acceptances/rejections (ACECF), rather than new ECF invoices.

| Field | Supplied values / handling |
|---|---|
| RNCEmisor | `131880681`: issuer of the invoice being acknowledged |
| RNCComprador | `131362702`: your company, issuing and signing the commercial decision |
| Estado | All 11 rows contain `1` (commercial acceptance) |
| FechaHoraAprobacionComercial | Preserve `25-10-2026 17:52:45` from the worksheet |
| MontoTotal | Serialize numeric Excel values with exactly two decimal places, including `0.00` |
| DetalleMotivoRechazo | Blank in this workbook; omit the optional element |

Invoice types represented are 31 (4), 33 (1), 34 (2), 44 (2), and 45 (2).
The counterpart RNC must not be replaced with your RNC. An approval filename is
**RNCComprador + eNCF + `.xml`**, for example `131362702E310000000001.xml`.

## Quick run

First make the new/changed modules available through your normal project build
workflow. These scripts deliberately never compile project code. No compilation,
tests, formatting, generation, authentication or document uploads were executed
while implementing these tools. As with the existing repo scripts, the normal
Mix environment/configuration must be available; Phoenix/Repo are not started.

From the repository root:

```sh
# Offline: import, build, sign, validate and publish the 11 ACECF documents.
bash server/sh/generate_fe_approvals.sh

# Online: real posts to the certification AprobacionComercial service.
bash server/sh/submit_fe_approvals.sh
```

Defaults use the supplied workbook, buyer RNC `131362702`, and the existing
`p12_companies/ans/22813977_identity.p12` / `credentials.txt` signing identity.
Generation verifies against the repository DigiFirma root and intermediate.
Submission defaults to `certecf`; `testecf` and `ecf` require explicit
`--environment` values. The existing WILTON BELTRE certificate signs on behalf of
the explicitly configured buyer; no company RNC is inferred from its subject.

Both commands resolve relative paths from your original working directory. Use
`--help` for the full options. For future workbooks/identities:

```sh
bash server/sh/generate_fe_approvals.sh \
  --workbook /path/commercial-decisions.xlsx \
  --output /path/new-approval-batch \
  --buyer-rnc 131362702 \
  --p12 /path/identity.p12 --credentials /path/credentials.txt \
  --ca /path/root.pem --intermediate /path/intermediate.pem

bash server/sh/submit_fe_approvals.sh \
  --batch /path/new-approval-batch \
  --buyer-rnc 131362702 \
  --p12 /path/identity.p12 --credentials /path/credentials.txt
```

## Outputs

The default generated batch is:

```text
fe/data-test/generated/131362702-25102026175246/
  acecf/                       # 11 signed ACECF files for this workbook
  manifest.json
  documents.csv
  SHA256SUMS
  README.md
```

The manifest includes raw worksheet values, serialized XML values, source row/cell
mappings, issuer/buyer/eNCF, requested state, supplied approval timestamp, and
workbook/schema/certificate/XML fingerprints. Amount serialization preserves the
numeric value (`7080` → `7080.00`, `228460.5` → `228460.50`); it does not round away
extra fractional value. All other supplied fields remain unchanged. The 88
populated cells in this workbook map to 88 XML fields; the 11 blank rejection
reasons are omitted. No new `FechaHoraFirma` is added to ACECF.

The generator reuses OTP ZIP/Saxy workbook reading, schema-driven ordering,
`TigooServer.Sign`, and shared signed-artifact verification. It validates each
complete signed ACECF against its XSD and checks its signature, trusted CA chain,
and mapped source values before publishing the batch. Output must be a new
directory; a lock and staging directory prevent partial publication by cooperating
runs. Passwords/private keys are never written to the output.

Source schema `fe/xsd/ACECF v.1.0.xsd` is unchanged. Its runtime copy replaces one
unsupported PCRE noncapturing group with an equivalent XSD regex group. See
`server/priv/fe/xsd/README.md`. Actual runtime schema hashes are recorded.

The workbook must have the expected first-sheet name and column names. Blank or
`#e` fields are omitted, explicit zeroes preserved, and unknown populated columns
rejected. Repeated eNCFs/upload filenames in the same buyer batch are rejected;
split overlapping invoice sequences from different counterpart issuers into
separate output batches. Future `Estado = 2` rows require a rejection reason.
Approval timestamps must be provided in `dd-MM-yyyy HH:mm:ss` text form and are
not replaced by the current time. Referenced invoices must already exist in DGII
with the matching issuer, buyer, emission date and total.

## Client and journal behavior

The client reuses DGII's seed → existing signer → ValidarSemilla → Bearer token
flow. It posts the **unchanged signed XML** as multipart field `xml`, with its
buyer-prefixed filename and `text/xml` content type, to:

```text
https://ecf.dgii.gov.do/CerteCF/AprobacionComercial/api/AprobacionComercial
```

The live contract returns `codigo` (string), `estado` (string) and **`mensaje`**
(array of strings). Codes `1`/`2` mean DGII registered/rejected the submitted
commercial decision. HTTP 400 can also carry that response structure; its body
is retained as error details. There is **no track ID or ECF result polling** for
this endpoint. Unknown results stop the runner instead of being treated as success.

Numeric response codes also arrive zero-padded (`"01"` / `"02"`). The classifier
normalizes them without modifying the recorded DGII response. On resume, an
`unknown` approval with a stored definitive response is reclassified only when
its kind, filename, checksum, requested decision and response identity match the
current validated job. An accepted receipt is then skipped without another POST.
The journal records this reclassification. A `sending` entry, a missing receipt,
or an unrecognized result remains blocked for reconciliation.

The XML's `Estado` is a separate concept: an ACECF with `Estado = 2` can be
successfully registered by DGII (`codigo = 1`). The journal retains both the
requested document decision and the DGII receipt result.

Submission uses the existing sequential journal runner, with preflight checks on
all file hashes, buyer/issuer/eNCF/amount/state/timestamp, signer and XSD before HTTP.
Default journal: `<batch>/submission-certecf.json`; use `--report PATH` to override.
It records `buyer_rnc`, upload intent, responses and failures without saving tokens
or passwords. Accepted entries are skipped on resume with the same journal.
There are no automatic POST retries or redirects. A rejected, unknown or
interrupted attempt requires reconciliation before another POST. Switching
journals does not carry earlier submission history. No additional queues, HTTP
controllers, database tables or schedulers are introduced.

## Reusable Elixir API

```elixir
alias TigooServer.Fe.{Client, CommercialApproval, Submission}

CommercialApproval.generate(
  workbook: "/path/commercial-decisions.xlsx",
  output: "/path/new-approval-batch",
  buyer_rnc: "131362702",
  p12_path: "/path/identity.p12",
  credentials_file: "/path/credentials.txt",
  trusted_certificates: ["/path/root.pem"],
  intermediate_certificates: ["/path/intermediate.pem"]
)
# {:ok, manifest} | {:error, %Generation.Error{}}

client = Client.new(
  environment: "certecf",
  issuer_rnc: "131362702", # Existing option name: the authenticated taxpayer is the buyer here.
  p12_path: "/path/identity.p12",
  credentials_file: "/path/credentials.txt"
)

Submission.run("/path/new-approval-batch", client, expected_document_type: "ACECF")
# {:ok, report} | {:error, %Client.Error{}, report_or_nil}

{:ok, response, client} = Client.send_approval(client, "/path/131362702E310000000001.xml")
Client.status(response, :approval)
```

`CommercialApproval.generate!/1` raises instead of returning an error tuple.
`CommercialApproval.Document.build!/3` is the reusable unsigned-document builder.
Lower-level upload calls require previously generated/validated signed artifacts;
they authenticate as necessary and return the updated client. Keep that client to
reuse token refreshes. Native executable overrides use the same options as the
existing tools. The batch generator supports the configured CA/CRL chain options.

Contracts read for this implementation:
[Authentication](https://ecf.dgii.gov.do/CerteCF/Autenticacion/help/index.html),
[Commercial approval](https://ecf.dgii.gov.do/CerteCF/AprobacionComercial/help/index.html),
[Commercial approval OpenAPI](https://ecf.dgii.gov.do/CerteCF/AprobacionComercial/api-docs/v1/definition.json).
The existing technical issuer-services PDF under `fe/` supplies filename conventions
and the DGII services PDF documents response-code meanings. Local validation does
not establish DGII acceptance or certificate delegation for a taxpayer.
