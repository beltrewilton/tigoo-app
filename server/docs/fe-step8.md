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

No URL for the matching issuer has been verified. Do not relabel an existing
certificate, trust the incoming leaf automatically, disable verification, or
interpret DGII's optional authentication wording as permission to issue tokens
without completing the configured authentication flow. On the fresh Step 8 run,
inspect the newly captured signer and any additional certificates/parts before
deciding the next correction. Step 8 is not proven passing by these changes.
