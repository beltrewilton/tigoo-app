# Restarting DGII Step 8 with captured evidence

## Flow confirmed against DGII documentation

1. DGII calls `GET https://evofitdb.tigoo.app/fe/autenticacion/api/semilla`.
2. Our application issues and stores a fresh seed. DGII signs it.
3. DGII uploads the signed seed as multipart field `xml` to
   `POST /fe/autenticacion/api/validacioncertificado`.
4. We validate the XML/signature profile, signer trust, signature integrity, and
   single-use seed before returning `token`, `expira`, and `expedido`.
5. DGII uploads invoices to `POST /fe/recepcion/api/ecf` using the bearer token.
6. We validate/persist the incoming invoice and return its signed ARECF.

The portal's **Enviar prueba de comprobantes** starts a fresh attempt. Do not
cancel the postulation or repeat Steps 1–7. Restarting our process clears its
in-memory seeds; always request a new seed after a restart. Historical signed
seeds are useful for offline signature inspection, not replay as fresh tokens.

Sources inspected:

- [DGII certification process, July 2025, PDF page 16, Steps 8–9](https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Documentacin%20sobre%20eCF/Documentaciones%20Proceso%20de%20Certificaci%C3%B3n%20FE/Proceso%20de%20Certificacion%20para%20ser%20Emisor%20Electronico.pdf).
- Local `fe/Descripcion Tecnica Emisores Electronicos.pdf`, pages 6–12:
  immutable signed XML, endpoint names, multipart field, output and ARECF.
- Local `fe/Descripcion Tecnica Servicios DGII.pdf`, pages 44–45:
  seed exchange with the DGII contributor simulator.
- Local `fe/Firmado de e-CF.pdf`: RSA-SHA256, SHA256 digest, empty reference,
  enveloped signature and inclusive canonicalization.
- [Viafirma CPS](https://cps.viafirma.do/PCSC-CPS-VIAFIRMARD.pdf), sections 2.1
  and 6.1.4, older CPS 2.4/3.0/3.1/3.2 and tax-certificate policy: published
  certificates and CA Issuers extension.
- [Digifirma certificate downloads](https://digi.camarasantodomingo.do/informacion-adicional/certificados-raiz/).

## Enable capture before retrying

Deploy the capture changes and add this to the running service's `.env-prod`:

```dotenv
FE_REQUEST_CAPTURE_DIRECTORY=/opt/tigoo-app/data/fe-request-capture/step8-run-1
```

Restart using the existing service procedure, then select **Enviar prueba de
comprobantes** in Step 8. This requires the authenticated DGII portal; this
repository does not contain a supported API for pressing that button.

Each matching FE request gets a separate folder under `requests/<uuid>/`:

| File | Contents |
| --- | --- |
| `request.json` | Request ID, timestamp, method, host, path and redacted headers |
| `multipart.json` | Field names, original filenames, lengths and SHA-256 hashes |
| `part-N.xml` / `.bin` | Original multipart payload bytes, saved before controller validation |
| `part-N.xml-certificate-M.pem` | Embedded public certificates; extraction does not establish trust |
| `request-body.bin` | Original JSON/urlencoded body when those parsers are used |
| `response-body.bin` | Seed, signed ARECF, or error response; successful authentication tokens are redacted |
| `response.json` | Status, redacted headers, archived-body hash and truncation flag |
| `root-N.crt`, `intermediate-N.crt`, `crl-N.crl` | Copies of configured public verification resources |
| `verifier-resources.json` | Original resource paths, hashes and native tool paths |

All multipart parts are inspected, including unexpected field names and additional
uploads. Files are **copied**, preserving Plug's temporary uploads for normal
processing. The multipart wire envelope/boundary itself is not reconstructed or
reformatted. Requests rejected by the multipart parser before its callback may
have only request metadata. Unparsed/unsupported content types are not consumed
by capture. The existing parser/validation limits remain in force; capture is
bounded to 8 MB per body/part/response. No body changes are made to live requests
or responses. JSON/XML token responses are redacted only in the archived copy.

Only the FE authentication/reception/commercial-approval path prefixes are
captured. POS checkout and non-FE requests are excluded. Capture does not implement
the later commercial-approval endpoint. Directories use `0700`, files `0600`;
bearer/cookie headers and token/password multipart fields are omitted/redacted.
Captures are not public static assets. Disable the environment setting after the
investigation and remove/archive old runs deliberately; there is no automatic
retention job. Capture IO failures are logged and do not change HTTP behavior.

The earlier `FE_AUTH_DIAGNOSTIC_DIRECTORY` setting still saves failed cryptographic
seed-verification artifacts. It is independent of the new all-request capture.

## Authoritative download commands

These are verified provider URLs, **not a claim that the published test chain
matches DGII's current signer**. Downloads do not change application trust.
Keep them separate from currently configured resources:

```bash
mkdir -p /opt/tigoo-app/fe/provider-downloads
cd /opt/tigoo-app/fe/provider-downloads

# Digifirma (PEM)
wget -nc https://digi.camarasantodomingo.do/assets/documents/certificado-raiz/digifirma-ca-raiz.crt
wget -nc https://digi.camarasantodomingo.do/assets/documents/certificado-raiz/digifirma-ca-subordinada-1.crt

# AVANSI / Viafirma production signing chains (DER)
wget -nc https://cps.viafirma.do/CA003_AVANSICERTIFICACION.crt
wget -nc https://cps.viafirma.do/CA007_VIAFIRMAQUALIFIEDCERTIFICATES.crt
wget -nc https://cps.viafirma.do/CA005_VIAFIRMAQTSPROOTCA.crt
wget -nc https://cps.viafirma.do/CA008_VIAFIRMAQUALIFIEDCERTIFICATES.crt

# Test intermediate named by DGII signer's CA Issuers URL, and its root (DER)
wget -nc https://cps.viafirma.do/subcatest.crt
wget -nc https://cps.viafirma.do/rootcatest.crt

for name in CA003_AVANSICERTIFICACION CA007_VIAFIRMAQUALIFIEDCERTIFICATES \
  CA005_VIAFIRMAQTSPROOTCA CA008_VIAFIRMAQUALIFIEDCERTIFICATES rootcatest subcatest
do
  if [ ! -e "$name.pem" ]; then
    openssl x509 -inform DER -in "$name.crt" -out "$name.pem"
  fi
done
```

Use a new empty directory to fetch a fresh provider snapshot; `-nc` deliberately
preserves an existing snapshot. Provider test roots must not be enabled for
ordinary production trust.

## Standalone inspection without Phoenix or compilation

Python 3, OpenSSL and xmlsec1 are sufficient; no third-party Python dependencies,
database, private key, running application or network requests are needed.

Inspect the already-captured seed from the repository root:

```bash
python3 server/scripts/inspect_fe_capture.py \
  --xml fe/diagnostics/signed-seed.xml \
  --roots fe/rootcatest.pem \
  --intermediates fe/subcatest.pem \
  --output /tmp/step8-inspection-1
```

Inspect a new copied request using the **actual trust-store snapshot from that
request**, replacing the example folder with the logged UUID:

```bash
capture_dir=/path/to/copied/requests/UUID
python3 server/scripts/inspect_fe_capture.py \
  --xml "$capture_dir/part-1.xml" \
  --roots "$capture_dir"/root-*.crt \
  --intermediates "$capture_dir"/intermediate-*.crt \
  --output /tmp/step8-inspection-2
```

Check `multipart.json` first: `part-1.xml` is an example, not an assumed field
position. Omit `--intermediates` if none were configured. Supply one certificate
per root/intermediate input file. Each output directory must be new. The script
saves the unchanged XML, extracted certificates/details, verification logs and
`report.json`. It reports signature integrity separately from certificate-chain
trust and exits nonzero if either fails. An integrity-only pass never issues a
token or authenticates a caller. This is not a live replay, XSD validation or
seed-freshness check; configured CRLs are archived but not checked by this helper.

## Established result and remaining evidence

The captured signer is:

```text
SHA-256: 3d0be20c8bd2917f0e2d5a8d4dac056b50993fa8ef5c9884798c58f940c59cbb
Issuer: VIAFIRMA QUALIFIED CERTIFICATES TEST
Required authority key identifier:
33:CD:2B:C1:F3:C3:DA:70:1C:6A:3A:25:62:33:E4:AE:08:0A:B2:88
```

The public `subcatest.crt` returned over HTTP, HTTPS and a fresh query has SKI:

```text
04:6E:4B:7C:B9:DC:3D:9D:39:A1:2F:48:8B:26:26:E5:BD:5E:4E:E0
```

Independent offline inspection confirms the XML signature is valid, but the
signer certificate does not verify against that intermediate. No examined
certificate matches the required key. `DGIIRootCertificateAuthority.zip`,
`camaracomercio.crt` and `camaracomercio 2.crt` contain the already-configured
Digifirma intermediate, not this Viafirma issuer.

## Matching 2024 chain recovered from Viafirma OCSP

The CRLs in `certs_content.txt` carry the same authority key identifier as
Pedro's certificate. Querying the official **HTTPS** OCSP service for that CertID
returns the matching intermediate inside the signed OCSP response. Querying the
intermediate's CertID returns the matching root, also inside a signed response.
The old static `subcatest.crt` and `rootcatest.crt` downloads are a different test
hierarchy; they must not be confused with these recovered certificates.

Recovered public certificates:

| File | Subject | Subject Key Identifier | SHA-256 fingerprint |
| --- | --- | --- | --- |
| `fe/viafirma-test-intermediate-2024.pem` | VIAFIRMA QUALIFIED CERTIFICATES TEST | `33CD2BC1F3C3DA701C6A3A256233E4AE080AB288` | `61AB86DBC7C7D25BADDFAF40804A2E55CB90A43F3575F03BD41184E281111453` |
| `fe/viafirma-test-root-2024.pem` | VIAFIRMA CERTIFICATION - TEST | `5ADE45CC2B655CF9BC15ABF03AE86495B6A0CEC7` | `FBF85AFCA27F80B6F9F10AFCB15B2A3F229DC22DDE338A8C9C998D0216EB211F` |

The intermediate is valid April 26, 2024–April 26, 2034. The root is valid
April 26, 2024–April 26, 2054. Root self-signature, Pedro's certificate chain,
CRL signature/revocation check, OCSP response signature, and full `xmlsec1`
verification of the captured seed all pass with this chain. This is not
integrity-only verification or automatic trust in an incoming leaf certificate.

Evidence, exact OCSP requests/responses and report are saved locally under
`fe/diagnostics/issuer-discovery-20261028/`. From the repository root, the
following commands re-download the response resources using the saved requests:

```bash
wget --header='Content-Type: application/ocsp-request' --header='Accept: application/ocsp-response' --post-file=fe/diagnostics/issuer-discovery-20261028/signer-status-request.der -O /tmp/viafirma-signer-status.der https://ocsptest.viafirma.do/ocsp
wget --header='Content-Type: application/ocsp-request' --header='Accept: application/ocsp-response' --post-file=fe/diagnostics/issuer-discovery-20261028/issuer-status-request.der -O /tmp/viafirma-issuer-status.der https://ocsptest.viafirma.do/ocsp
```

Decode the response resources (this parse operation alone does not verify trust):

```bash
openssl ocsp -respin /tmp/viafirma-signer-status.der -text -noverify | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/viafirma-test-intermediate-2024.pem
openssl ocsp -respin /tmp/viafirma-issuer-status.der -text -noverify | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/viafirma-test-root-2024.pem
```

Compare their fingerprints against the recorded values above before provisioning
trust. The root was obtained through the provider's authenticated HTTPS endpoint.
Validate the chain and signed OCSP response independently:

```bash
openssl verify -check_ss_sig -CAfile fe/viafirma-test-root-2024.pem fe/viafirma-test-root-2024.pem
openssl verify -CAfile fe/viafirma-test-root-2024.pem -untrusted fe/viafirma-test-intermediate-2024.pem fe/diagnostics/dgii-signer.pem
openssl ocsp -respin /tmp/viafirma-signer-status.der -CAfile fe/viafirma-test-root-2024.pem -verify_other fe/viafirma-test-intermediate-2024.pem
xmlsec1 --verify --enabled-reference-uris empty --enabled-key-data x509 --trusted-pem fe/viafirma-test-root-2024.pem --untrusted-pem fe/viafirma-test-intermediate-2024.pem fe/diagnostics/signed-seed.xml
```

For production's certification deployment, copy the two recovered files into
`/opt/tigoo-app/fe/`. Replace only the old `rootcatest.pem` entry in
`FE_TRUSTED_CERTIFICATES` with `/opt/tigoo-app/fe/viafirma-test-root-2024.pem`, and
replace only the old `subcatest.pem` entry in `FE_INTERMEDIATE_CERTIFICATES` with
`/opt/tigoo-app/fe/viafirma-test-intermediate-2024.pem`. Preserve the other
configured provider entries. Restart, request a fresh Step 8 attempt, and inspect
its capture. Live token issuance and subsequent invoice reception remain to be
confirmed; offline success does not establish that the full certification step
has passed. These test CAs are for the certification deployment, not normal
production invoicing trust.

## Reception failure after authentication succeeded

The capture `3ca8e6b5-26a0-4bf8-9343-f0d9bcc4b164` contains E31
`E310000000001`. Its incoming XML passes the unchanged official E31 XSD under
`xmllint`, and its signature verifies with the recovered Viafirma test chain.
Both email fields were falsely rejected by xmerl's unimplemented XSD `\w`
character class. Our returned ARECF was structurally valid and correctly signed
with the receiver's Digifirma identity, but reported `Estado=1` and
`CodigoMotivoNoRecibido=1` (specification error). Authentication was no longer the
blocking step.

Inbound invoice/ARECF XSD validation now uses the same native `xmllint` tool as
the existing eCF generation flow. Official schemas are unchanged; digital
signatures still use the original uploaded bytes. Validation uses a private
temporary directory, `--nonet` and a five-second command timeout. A missing tool
or unavailable schema returns service-unavailable rather than a false invoice
rejection. Native validation errors are not logged with customer field values.
Seed authentication and POS checkout are not changed by this fix.

Before restarting the updated service, confirm the binary on production:

```bash
command -v xmllint
```

If missing on Ubuntu, install `libxml2-utils`. Set the executable path in
`.env-prod` if needed:

```dotenv
FE_XMLLINT_PATH=/usr/bin/xmllint
```

Deploy, restart, then select **Enviar prueba de comprobantes** again. Keep request
capture enabled. A fresh request is required because seeds/tokens are temporary.
The next capture should show whether the valid invoice was persisted and an
`Estado=0` ARECF returned. Full live completion still requires confirmation from
DGII.
