# CerteCF Step 4 simulation

The Elixir CSV adapter reuses `Fe.Generation` for XSD mapping, signing, chain and
signature verification, immutable batch publication and RFCE derivation.
`Fe.Submission` supplies seed/sign/token authentication, ordered posts, result
consultation and resumable journals. No new HTTP stack or database is required.

Run from the repository root after building through the project's normal workflow:

```bash
bash server/sh/generate_fe_simulation.sh --issuer-address 'SANTO DOMINGO, REPUBLICA DOMINICANA'
bash server/sh/submit_fe_simulation.sh --batch fe/data-test/generated/step4
```

Both runners use `--no-compile --no-deps-check --no-start`. Existing compiled
modules older than their source are refused before generation or HTTP. Rebuild
through the normal project workflow after any Elixir changes; rerunning a shell
script alone does not load those changes. Submission also checks the signed ECF
adjustment breakdowns, so rebuilding does not make an old invalid batch valid.
Existing compiled
modules/dependencies and the existing OpenSSL, xmlsec1, xmllint and CA files are
required. Existing Mix configuration environment variables remain required.
Generation is offline. Only the submit command makes fiscal HTTP requests.
The identity defaults to `p12_companies/ans/22813977_identity.p12`, with password
read privately from its adjacent `credentials.txt`. Issuer: EVOFIT WB SRL,
131362702; the existing personal signer does not change the XML issuer.

## Cases and assumptions

| Type | Full ECFs | Scenario |
| --- | ---: | --- |
| 31 | 4 | CSV fiscal sales |
| 32 >= 250,000 | 2 | Largest sales, quantities/discounts multiplied to reach threshold |
| 32 < 250,000 | 4 | CSV consumer sales; also generate four RFCEs |
| 33 | 1 | Additional charge referencing case 31-1 |
| 34 | 2 | Partial return of 31-2; full cancellation of 31-3 |
| 41 | 2 | Simulated purchases using CSV goods and customer as supplier |
| 43 | 2 | Simulated minor expenses |
| 44 | 2 | Simulated special-regime buyers |
| 45 | 2 | Simulated government buyers |
| 46 | 2 | Simulated exports, zero-rated, foreign buyer identifiers |
| 47 | 2 | Simulated nonresident commercial advisory services concerning CSV products, foreign identifiers |

There are 25 signed ECFs plus four signed RFCEs. The CSV has 95 lines across 71
invoices; the largest source invoice is RD$88,400. Invalid ten-digit customer
identifiers are excluded and recorded rather than corrected. Negative discounts
become surcharges. Amount-based line discounts and surcharges include matching
sub-discount/sub-surcharge tables with type `$` and amounts summing to the line
adjustment. Simulation preflight rejects missing or unbalanced breakdowns.
Computation uses Decimal and tax-inclusive 18% for taxable
cases, following existing checkout behavior. Purchases assume 100% VAT withholding
and 3% ISR; nonresident payments assume 27% ISR. These are explicit invented
scenario assumptions authorized by the user, not verified historical tax treatment
or proof of customer eligibility as a government/special-regime taxpayer.

`ValorPagar` follows the format's standard formula: `MontoTotal - MontoAvancePago
+ SaldoAnterior`. These scenarios have no advance/prior balance, so it equals
`MontoTotal`. Withheld ITBIS/ISR remain separate totals and are not deducted from
this field. Simulation preflight and submission enforce this formula; Norma
10-07 adjustments are outside these scenarios.

Type 47 contains services only (`IndicadorBienoServicio=2`). Its invented advisory
service description identifies the source product; CSV quantities/net amounts
become simulated service units/fees. Original goods remain in provenance, not as
goods sold by the foreign supplier. Generation and submission reject type-47
goods lines even though the XSD enum permits them.

Simulation issue dates default to today's GMT-4 date. Original B-series invoice
numbers, dates, CSV records, product lines, multipliers and overrides are retained
in `manifest.json`. The issuer address above is a simulation placeholder, not a
verified legal address. Override it with `--issuer-address` as appropriate.

Use `--case-overrides path.json` to supply corrected scenario data. The JSON maps
case IDs to flattened generator fields; values are strings or null (delete):

```json
{"45-1": {"RNCComprador": "REPLACE_WITH_VALID_RNC", "RazonSocialComprador": "Government buyer"}}
```

The example is a template and must be replaced before use. All overrides must
still pass the matching XSD and business checks. Reserved document identity fields
cannot be overridden. DGII may reject invented roles based on taxpayer registry
checks; local XSD/signature validation does not establish fiscal acceptance.

## Output and sequence handling

Default output: `fe/data-test/generated/step4`. Includes `manifest.json`,
`documents.csv`, `SHA256SUMS`, `ecf/recepcion`, `rfce`, and
`ecf/consumo-menor-250000`. Each row's source and assumptions are in the manifest.
Signed files are never reformatted or overwritten. The XSD always determines
element casing, including `MontoSubRecargo` versus `MontosubRecargo`.

The persistent ledger is `fe/data-test/simulation-sequences-131362702.json`.
Initial sequences have a lower bound of 1 per type as requested. Before each
reservation, the generator scans ECF manifests for this issuer under
`fe/data-test/generated` (override with `--history-directory`). It skips past the
highest locally generated number per type, including earlier certification
stages and failed simulation batches. Commercial approval manifests are excluded.
Reservations advance before
signing and survive failure. Never delete/reset the ledger or reuse another
ledger for the same issuer. This tool cannot discover sequences used outside its
ledger/history. Keep all prior manifests; remotely used numbers absent from local
history still require reconciliation before submission. A portal restart does
not make previously used eNCFs available again.

For a new attempt, select a fresh output directory while keeping the same ledger:

```bash
bash server/sh/generate_fe_simulation.sh --output fe/data-test/generated/step4-attempt-2
bash server/sh/submit_fe_simulation.sh --batch fe/data-test/generated/step4-attempt-2
```

Resume an interrupted submission using the same batch and journal. Accepted
documents are skipped, saved track IDs are consulted, and uncertain posts are
not automatically repeated. Do not regenerate simply to resume polling.
Simulation batches are restricted to CerteCF. Submission sends 21 ordinary ECFs
and four RFCEs. After each RFCE is accepted, upload its corresponding full signed
ECF from `ecf/consumo-menor-250000` individually through the portal.

The XML tools preserve the exact signed documents, timestamp and RFCE security
code for later printed representations. They do not generate Step-5 printable
documents or QR images. Use the separate reusable
`bash server/sh/generate_fe_printed_invoices.sh --batch BATCH_DIRECTORY` runner
described in [fe-printed-invoices.md](fe-printed-invoices.md) to create them from
these same signed values after successful submission.

API contracts reused by the existing client:
[Authentication](https://ecf.dgii.gov.do/CerteCF/Autenticacion/help/index.html),
[Reception](https://ecf.dgii.gov.do/CerteCF/Recepcion/help/index.html),
[Results](https://ecf.dgii.gov.do/CerteCF/ConsultaResultado/help/index.html),
[RFCE](https://fc.dgii.gov.do/certecf/recepcionfc/help/index.html).
