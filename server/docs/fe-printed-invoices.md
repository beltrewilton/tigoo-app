# Step 5 printed invoices

Generate offline PDF representations of the successful Step-4 batch:

```bash
bash server/sh/generate_fe_printed_invoices.sh
# Same tool for a future batch:
bash server/sh/generate_fe_printed_invoices.sh --batch fe/data-test/generated/step4-attempt-6 --output fe/data-test/generated/step4-attempt-6/printed-v2
```

The default source is `fe/data-test/generated/step4-attempt-6`. Output defaults to
`BATCH/printed`. Existing output is refused. Source XMLs, manifests, journals and
sequence ledgers are never modified. This command performs no authentication or
fiscal HTTP requests and does not compile, test, format or start Phoenix/Repo.

## Prerequisites

Rebuild the new modules through the normal project workflow before running.
The runner refuses missing or stale compiled modules. Existing Mix configuration
environment variables still apply. It reuses repo XML parsing, hashing, XSD and
signature/chain verification and the existing CA files; OpenSSL, xmlsec1 and
xmllint must remain available.

PDF rendering requires installed Chrome/Chromium. macOS Google Chrome is detected
automatically; override with `--chrome-path /path/to/chrome`. QR encoding and SVG
rendering run entirely in Elixir through the `qqr` Hex dependency (0.2.x,
compatible with this project's Elixir 1.15 requirement). Fetch dependencies using
`mix deps.get` from `server`, then rebuild through the normal workflow before
running the unchanged shell command. The dependency lock will be updated during
that fetch. No Homebrew QR package, Python, remote QR service or external fonts
are required. Chrome remains the native HTML-to-PDF renderer.

Optionally pass `--logo path/to/logo.png` (or JPEG, below 500 KB) for a clean logo.
The attached receipt photograph is a layout reference; no logo is extracted from
it. Without a logo the signed issuer name is the heading. The printed issuer
address comes from the accepted XML, even if that contains a simulation address;
the screenshot address is not silently substituted.

## Output

- `individual/`: one PDF per full ECF, named `RNCEmisor + eNCF.pdf` (25 here).
- `upload/`: one multipage PDF per portal category (11 here), containing all
  corresponding invoices: 31, 32 >=250000, 33, 34, 41, 43, 44, 45, 46, 47 and
  32 <250000. Bundling is a practical mapping to the single file input per category.
- `html/`: standalone receipt layouts and category layouts for inspection.
- `qr/`: QR SVGs generated locally, level L, four-module quiet zone; strict version
  8 by default, or at least 8 with the explicit automatic-version option.
- `manifest.json`: source and PDF hashes, invoice/category mapping, security codes,
  exact QR URLs and combined upload size. `SHA256SUMS` covers retained outputs.

Layout follows the attached receipt: narrow 80 mm centered receipt on A4 pages,
issuer header, client/document identifiers, dashed dividers, product/service lines,
discounts/surcharges, fiscal totals and footer. It adds the required electronic
document title, eNCF, sequence expiry where present, reference details, signature
timestamp, security code and QR. Payments, SKU, salesperson or delivery charges
absent from XML are not invented. Discounts already included in item amounts are
labelled accordingly, not deducted twice. Long receipts can span multiple pages;
each invoice starts on a new page in grouped PDFs.

The journal must be complete, belong to CerteCF and match the exact manifest.
Every document must have matching accepted/conditionally accepted journal data.
XML hashes, schema, signatures and trust chain are verified before rendering.
For consumption <250000 the journal proves RFCE acceptance, not the separate
manual full-ECF portal upload: confirm those four uploads succeeded before Step 5.
Their receipts use the full ECF signature's security code, checked against RFCE.

QR URLs use the CerteCF `consultatimbre` service for normal documents and
`consultatimbrefc` for low-amount consumption. Dates, totals, identifiers and the
first six signature characters come from final signed ECF bytes. URL values are
percent-encoded; foreign identifiers are not substituted for RNCComprador.
The default `--qr-version 8` checks capacity before forced encoding and returns a
clear error if the exact URL requires a larger version. qqr 0.2.0 otherwise
crashes for oversized forced-version payloads. Its automatic capacity selection
is used first to avoid that defect, without modifying installed dependencies.

Explicit `--qr-version auto` permits the smallest fitting version, with a minimum
of 8. Each document's actual `qr_version` is recorded in the manifest and higher
versions are announced in CLI output. This is a rendering option, not a claim of
DGII approval: the technical document specifies version 8; confirm larger versions
are acceptable before uploading those PDFs. Signed values and QR URLs are never
shortened or changed to fit. No validation URL is requested during PDF creation.

The sum of the 11 `upload/` PDFs must be <=10,000,000 bytes, a conservative
interpretation of the portal's combined 10 MB limit. Oversized runs are discarded.
Review PDFs and scan QR codes before uploading the category PDFs manually. The
tool does not submit PDFs or claim DGII's printed-representation approval.

Requirements: the repo's `Formato Comprobante Fiscal Electrónico (e-CF) V1.0.pdf`
and DGII's `Descripción Técnica de Facturación Electrónica` (Consulta timbre and
Consulta timbre FC). QR encoding options follow the
[QQR API](https://hexdocs.pm/qqr/QQR.html). The wrapper also verifies the matrix
has the dimensions corresponding to the recorded version before SVG rendering
(49x49 modules for version 8).
