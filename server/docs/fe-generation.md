# Reusable Elixir ECF/RFCE generation

This workflow reads **only the first worksheet, named ECF**, from a DGII
certification workbook. The second worksheet is not imported. It generates a
complete signed ECF for every data row and a separate signed RFCE for each
type-32 ECF with `MontoTotal < 250000.00` DOP. Exactly 250000.00 uses normal ECF
reception. A type other than 32 is never routed to RFCE based on its amount.

All workbook parsing, mapping, rules, RFCE derivation, orchestration and reporting
are implemented in Elixir in this repository. OTP ZIP, Saxy, Decimal and Jason
are used. Existing `TigooServer.Sign` performs signing with OpenSSL and xmlsec1;
`xmllint` validates the corresponding XSD. There is no Python dependency.

## Quick run

The new modules must first be built through the project's normal build workflow.
**The implementation has not been compiled, run, tested or formatted as part of
this change.** The shell command deliberately uses `mix run --no-compile
--no-deps-check --no-start`; it never builds modules or starts Phoenix/Repo.
Missing or stale BEAM files must be addressed in your normal build workflow
before running it. Do not use the new source with stale compiled modules.

From the repository root, after the modules are available:

```sh
bash server/sh/generate_fe_certification.sh
```

Defaults:

- Workbook: `fe/data-test/131362702-25102026004903.xlsx`.
- Authorized issuer RNC: `131362702`.
- Signing identity: `p12_companies/ans/22813977_identity.p12`.
- Credentials: `p12_companies/ans/credentials.txt`, with one `Password: ...` field.
- Trust: repository DigiFirma root and intermediate under `fe/`.
- Runtime schemas: `server/priv/fe/xsd/` through the application's priv directory.
- Output: `fe/data-test/generated/131362702-25102026004903/`.

Your confirmation authorizes the WILTON BELTRE signing identity for EVOFIT WB
SRL, RNC 131362702. The tool requires the explicit issuer RNC rather than deriving
a company RNC from the individual certificate subject. It preserves the DGII
worksheet's supplied test issuer names, dates, payment amounts and identifiers.

For a future workbook or a different identity:

```sh
bash server/sh/generate_fe_certification.sh \
  --workbook /absolute/path/cases.xlsx \
  --output /absolute/path/new-batch \
  --issuer-rnc 131362702 \
  --p12 /absolute/path/identity.p12 \
  --credentials /absolute/path/credentials.txt \
  --ca /absolute/path/root.pem \
  --intermediate /absolute/path/intermediate.pem
```

Paths passed to the shell resolve from your original working directory. Optional
`--ca`, `--intermediate` and `--crl` accept repeated values. Use `--xmlsec`,
`--openssl` and `--xmllint` to override executables. These tools must be available
on PATH otherwise. Passwords are never CLI arguments or written to reports.

`--strict-arithmetic` refuses a batch with any arithmetic observation. The default
preserves source amounts and records observations for review. This workbook has
known supplied payment/total differences and a one-cent total/component
difference; strict mode can therefore reject it without producing a batch.

## Outputs

For the supplied workbook the expected counts are **25 ECFs, 21 normal-reception
documents, four low-amount full ECFs, and four RFCEs**. These counts are not
hard-coded: future workbooks can contain a different number of data rows.

```text
<output>/
  ecf/
    recepcion/                 # 21 full ECFs for normal reception
    consumo-menor-250000/       # 4 full ECFs for certification portal upload
  rfce/                        # 4 summaries for RFCE reception
  manifest.json
  documents.csv
  SHA256SUMS
  README.md
```

Every XML filename is `RNCEmisor + eNCF + .xml`. ECFs and RFCEs intentionally
share the filename and live in different directories. Do not append `.signed`
or an RFCE prefix to the upload filename.

The manifest includes workbook/schema/certificate hashes, row and cell mappings,
per-document validation flags, arithmetic observations, and a stable dependency
order. The workbook puts notes before their referenced invoices; use
`normal_reception_order` and wait for required acceptance before dependent notes.
References outside a future workbook are listed in `external_reference_encfs`;
their prior acceptance must be checked separately. Credit-note limits checked by
this tool include only notes present in the current workbook, not earlier notes
submitted elsewhere.

The exporter uses a sibling lock directory and a staging directory. It refuses
existing outputs and publishes only after the entire batch passes. A failed run
cleans up its staging directory. Abrupt OS/process termination can leave a lock
or staging directory; confirm no process owns it before removing it. Existing
signed batches are never replaced. Choose a new `--output` for another run.

## Elixir API

```elixir
alias TigooServer.Fe.Generation

Generation.generate(
  workbook: "/absolute/path/cases.xlsx",
  output: "/absolute/path/new-batch",
  issuer_rnc: "131362702",
  p12_path: "/absolute/path/identity.p12",
  credentials_file: "/absolute/path/credentials.txt",
  trusted_certificates: ["/absolute/path/root.pem"],
  intermediate_certificates: ["/absolute/path/intermediate.pem"]
)
# {:ok, manifest} | {:error, %TigooServer.Fe.Generation.Error{}}
```

`generate!/1` raises on failure. A caller may supply `password: password` in
memory instead of `credentials_file`. Additional API options are
`schema_directory`, `strict_arithmetic`, `crls`, `xmlsec_path`, `openssl_path`,
`xmllint_path`, and `on_document: fn record -> ... end`. The callback runs after
each staged document is validated; it does not mean the entire batch has been
published yet. The API falls back to existing `:fe_authentication` native-tool
and CA configuration when these options are omitted.

Modules can also be used independently:

| Module | Responsibility |
|---|---|
| `Generation.Workbook.read!/1` | Read XLSX rows and retain cell provenance |
| `Generation.Schema.load!/2` | Select the matching XSD and record its hash |
| `Generation.Document.build_ecf!/3` | Build an unsigned schema-ordered ECF and source mappings |
| `Generation.Document.assert_source_preserved!/3` | Compare every mapped source field against signed bytes |
| `Generation.Document.build_rfce!/2` | Derive an unsigned RFCE from a finalized signed ECF |
| `Generation.Rules` | Business checks, Decimal arithmetic observations, reference order |
| `TigooServer.Sign.sign/4` | Existing XML signature generation and pinned verification |

`Document` builders are pure construction helpers; callers using them outside
the batch API must perform signing, XSD validation and trust checks themselves.
`build_rfce!/2` checks signature structure and extracts its value; it does not
independently establish cryptographic trust in an arbitrary supplied document.
The batch passes only ECF bytes it just signed and verified.

## Mapping and validation policy

- Trim header whitespace; map `ENCF` to `eNCF` and `NumeroLineaDoR` to the global
  adjustment section's `NumeroLinea`.
- Treat blank cells and the literal `#e` as absent. Preserve zero values.
- Map indexed headers to nested repetitions, including item codes, subdiscounts,
  subcharges, additional taxes, payment forms, phones, subtotals and pagination.
- Select element spelling, nesting, order and cardinality from the document's
  XSD. `MontosubRecargo` is an input alias only; the selected XSD's exact spelling
  wins. Unknown, ambiguous or duplicate targets fail; no populated fields vanish.
- Keep all imported amount/identifier strings out of floating-point arithmetic.
  Numeric Excel dates use workbook date-system/style metadata. ISO date cells,
  inline strings and shared strings are supported. Numeric time fractions,
  formulas and Excel error cells fail explicitly. Text identifiers are preferred
  when leading zeros matter; all-zero number formats are also recognized.
- Add `FechaHoraFirma` immediately before signing, formatted at fixed GMT−4.
  The worksheet cannot override it. Preserve historical `FechaEmision` values.
- Check buyer identity exclusivity, type-32 identification at the threshold,
  reference fields, calendar dates, conditional taxes/retentions/currency fields,
  reference dates, credit-note limits within the workbook and reference cycles.
- Validate every complete signed ECF and RFCE against the corresponding XSD.
  Verify each signature with the pinned leaf and configured trusted CA chain.
  No Phoenix task supervisor or database connection is needed.
- Derive `CodigoSeguridadeCF` from the first six whitespace-normalized Base64
  characters of the full ECF's `SignatureValue`. Derive RFCE fields from that ECF,
  sign the summary separately, and check its security code, totals and signer.
- Preserve final signed bytes; never reformat or re-sign the ECF after generating
  its RFCE. Reports contain hashes and mappings, never passwords or private keys.

The registry supports the current inline XSD sequence format. An unsupported XSD
compositor fails explicitly. These checks do not reproduce every DGII fiscal
validation or its external RNC/sequence registries. XSD and local cryptographic
success do not establish DGII acceptance. No source amount is silently repaired.

See `server/priv/fe/xsd/README.md` for the existing type-31/RNC compatibility
changes and the RFCE regex-only adaptation. Original `fe/xsd` files are untouched.

## Authentication, requests and responses

Generation is offline and requires no seed or access token. Delivery is implemented
by `TigooServer.Fe.Client` and the [submission runner](fe-submission.md), separately
from generation. The client obtains a **DGII** seed, signs it using the same reusable signer,
exchanges it using `/autenticacion/api/autenticacion/validarsemilla`, retains
`token`, `expira`, `expedido`, and sends `Authorization: Bearer <token>`.

- Normal ECF reception returns `trackId` and an error field; the client must
  consult the result before treating the document as accepted.
- RFCE reception returns validation status directly, including `codigo`,
  `estado`, `mensajes`, `encf`, and `secuenciaUtilizada`.
- The portal's four full low-amount ECF uploads follow acceptance of the
  corresponding RFCEs.

Do not confuse DGII's `validarsemilla` with the issuer/receiver convention
`/fe/autenticacion/api/validacioncertificado`. ARECF is a receiver acknowledgement,
not a DGII trackId response. This tool does not mint tokens, send documents,
poll DGII or alter the existing authentication/reception controllers. The
provided technical PDFs under `fe/` remain the service-contract references.
