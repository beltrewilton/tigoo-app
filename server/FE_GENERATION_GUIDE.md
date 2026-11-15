# DGII e-CF generation reference

Reference: `fe/Formato Comprobante Fiscal Electrónico (e-CF) V1.0.pdf`,
October 2025 edition. Page numbers below are the printed page numbers; the PDF
viewer page is one higher because of the cover.

`sh/generate_fe_certification.sh` delegates to `Generation.CLI` and
`Generation.generate/1`. The onboarding XLSX upload uses that same generation
API. These rules therefore apply to both entry points.

## Currency interpretation

- Printed pp. 27–28: `OtraMoneda` is conditional on foreign-currency billing.
  `TipoMoneda` identifies that foreign currency; `TipoCambio` is required when
  a currency code is present and must be positive.
- Printed p. 33: `MontoTotalOtraMoneda` is conditional on the presence of a
  foreign-currency amount in the header.
- Printed p. 43: a populated `OtraMonedaDetalle` requires its foreign-currency
  unit price and item amount.
- Printed p. 62, Table II: the permitted foreign-currency codes exclude DOP.
  The bundled XSD currency enumerations also exclude DOP.

A missing currency is treated as local DOP, recorded as `currency: "DOP"` in
that document's manifest record. The generator must **not** inject
`<TipoMoneda>DOP</TipoMoneda>` or create an `OtraMoneda` section for a local
invoice. This replaces the earlier explicit DOP XML default, which was invalid
against the bundled XSDs.

If the workbook supplies foreign-currency fields without a currency code, the
generator reports an actionable error rather than guessing a conversion,
dropping supplied amounts, or publishing an invalid DOP currency tag. An
explicit foreign code and its supplied values are preserved. XSD validation
checks the code against the schema's enumeration.

## Existing validation layers reviewed

- `Workbook`: imports the first `ECF` worksheet without float conversions;
  blank cells and `#e` are absent values.
- `Schema` / `Document`: resolve source columns to schema paths; emit elements
  in schema order; enforce required nodes and repetition bounds; preserve
  imported cell values in the signed XML.
- `Rules`: check document type, issuer, identifiers, dates, buyer identification,
  tax and withholding conditions, currency conditions, credit/debit references,
  reference order, and type-47 service lines.
- `Artifact`: validates every generated XML against the type-specific XSD,
  verifies its signature and certificate chain, and pins checksums.
- `Generation`: publishes the batch only after validation completes. The
  original signed bytes are kept for submission, with RFCE derivation for
  eligible low-value consumption invoices.

Arithmetic differences are reported in `source_arithmetic_observations`, with
source values preserved. CLI `--strict-arithmetic` rejects those differences.
This review does not establish exhaustive coverage of every conditional PDF
rule beyond the checks described here, nor DGII acceptance. No generation,
compilation, formatting, tests, or DGII submissions were run for this review.
