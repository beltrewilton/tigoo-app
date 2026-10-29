# DGII Steps 10–11: receive commercial approvals

## Flow and scope

Sources reviewed before implementation:

- [DGII certification process, Steps 10–11](https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Documentacin%20sobre%20eCF/Documentaciones%20Proceso%20de%20Certificaci%C3%B3n%20FE/Proceso%20de%20Certificacion%20para%20ser%20Emisor%20Electronico.pdf).
- Local `fe/Descripcion Tecnica Emisores Electronicos.pdf`, pages 11–12:
  POST endpoint, multipart `xml`, bearer authentication, HTTP 200/400 responses.
- Packaged `server/priv/fe/xsd/ACECF v.1.0.xsd` and existing commercial-approval
  document validator: required fields, states, amounts, dates and rejection reason.

DGII authenticates using our existing seed endpoints, then posts a signed ACECF:

```text
POST https://evofitdb.tigoo.app/fe/aprobacioncomercial/api/ecf
Authorization: Bearer <token issued by our authentication endpoint>
Content-Type: multipart/form-data
xml: <signed ACECF file>
```

The hostname determines the tenant. Authentication, upload handling and the
5 MB file limit are shared with invoice reception. The new endpoint validates
the ACECF XSD with `xmllint`, business fields with the existing approval document
validator, and the original signed bytes/certificate chain with `xmlsec1`.
The certificate fingerprint must match the authenticated token's certificate.
The invoice's `RNCEmisor` must match the active company in the hostname tenant;
`RNCComprador` identifies the party sending its approval. The certificate's
personal subject identifier is not compared to either company RNC.

The endpoint saves the exact signed XML, its SHA-256, signer fingerprint, issuer,
buyer, eNCF, amount, emission date, state, approval timestamp and rejection reason
in `[tenant].fe_received_approvals`. Dates retain their validated DGII text
representation. No operational sale is required, created or modified. Incoming
approvals do not mutate sales, payments, stock, POS test mode or invoice counters.

## Responses and retries

- Valid document persisted: HTTP 200, `OK`.
- An exact retry (same issuer, buyer, eNCF and XML SHA-256): HTTP 200, without a
  second row. A unique index handles concurrent retries.
- Both ACECF `Estado=1` (commercial acceptance) and `Estado=2` (commercial
  rejection) are valid incoming documents; commercial rejection is not an HTTP
  transport failure. Rejection requires `DetalleMotivoRechazo`.
- Invalid schema, signature, fields or recipient company: HTTP 400.
- Missing/invalid/expired bearer token: HTTP 401.
- Unknown tenant: HTTP 404; oversized upload: HTTP 413.
- Missing migration, unavailable company configuration, verifier or database:
  HTTP 503. A storage failure is never acknowledged as success.

No ARECF or newly signed ACECF is returned. The existing request capture already
covers the commercial-approval prefix, preserving incoming files, certificates,
verification resources and the HTTP response before processing completes.
Path normalization includes this endpoint so capitalization differences are
handled like the authentication and invoice-reception paths.

## Deployment before pressing the Step 10 button

1. Deploy these changes and apply tenant migration
   `20261028000000_create_fe_received_approvals.exs` to `evofitdb` (and any other
   tenant using this endpoint) through the normal tenant migration workflow.
2. Keep the working Viafirma certification trust chain, `xmlsec1` and `xmllint`
   configuration. This endpoint needs no new signing certificate or tenant secret.
3. Keep `FE_REQUEST_CAPTURE_DIRECTORY` enabled, optionally changing it to a fresh
   `step10-run-1` directory, then restart the service.
4. Verify the registered domain is `evofitdb.tigoo.app` for authentication and
   commercial approval, and press **Enviar prueba de aprobaciones comerciales**.
5. Inspect the captured ACECF and HTTP response, and confirm saved rows in
   `evofitdb.fe_received_approvals`. HTTP 200 confirms receipt of the approval,
   not independent completion of the DGII certification workflow.

The code has not been compiled, tested or formatted during this implementation.
Live certification readiness must be confirmed after deployment and migration.
