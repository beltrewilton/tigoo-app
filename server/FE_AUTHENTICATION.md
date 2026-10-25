# FE certificate authentication

`GET /fe/autenticacion/api/semilla` issues an unsigned XML seed with `valor` and
`fecha`. The transmitter signs that document using their own private key, then
uploads it as multipart field `xml` to
`POST /fe/autenticacion/api/validacioncertificado`.

Both endpoints support JSON and XML through `Accept`; XML is the default.
Paths are case insensitive. Deploy these endpoints behind HTTPS.

## Runtime setup

`xmlsec1` is an operating-system executable, not a Hex package. Install it on
each backend host with the OpenSSL engine. The commands below are instructions
to run manually; they do not compile or start the Elixir app.

### macOS M1 / Apple Silicon

With [Homebrew](https://brew.sh/) installed in its Apple Silicon prefix:

```sh
/opt/homebrew/bin/brew install libxmlsec1 openssl@3
/opt/homebrew/bin/xmlsec1 --version
/opt/homebrew/bin/xmlsec1 --list-transforms --crypto openssl
```

The transform list should include `rsa-sha256`, `sha256`, `enveloped-signature`,
and C14N support. Homebrew calls the package **libxmlsec1**, but the executable
is **xmlsec1**. See the [official formula](https://formulae.brew.sh/formula/libxmlsec1).

Set the executable path in the backend environment:

```sh
export FE_XMLSEC_PATH=/opt/homebrew/bin/xmlsec1
```

For the certificate commands below, use Homebrew OpenSSL rather than the macOS
system version:

```sh
export PATH="/opt/homebrew/opt/openssl@3/bin:$PATH"
```

### Ubuntu

Use the packages matching your Ubuntu release. Run `cat /etc/os-release` if unsure.

```sh
sudo apt update
```

| Ubuntu release | Installation command |
| --- | --- |
| 26.04 LTS | `sudo apt install xmlsec1 libxmlsec1-openssl1 openssl` |
| 24.04 LTS | `sudo apt install xmlsec1 libxmlsec1t64-openssl openssl` |
| 22.04 LTS | `sudo apt install xmlsec1 libxmlsec1-openssl openssl` |

Check the executable and OpenSSL engine:

```sh
/usr/bin/xmlsec1 --version
/usr/bin/xmlsec1 --list-transforms --crypto openssl
export FE_XMLSEC_PATH=/usr/bin/xmlsec1
```

Ubuntu 26.04 provides XMLSec 1.3.x. Older LTS releases provide 1.2.x with Ubuntu's
package updates; these installation steps alone do not establish compatibility
with this endpoint. Prefer 26.04 for a new deployment, keep security updates
installed, and verify the signature flow when runtime validation is authorized.
Package names are listed in the [Ubuntu package index](https://packages.ubuntu.com/search?keywords=xmlsec1).

### Where the PEM files come from

The filenames in the earlier example were placeholders, not files supplied by
DGII. PEM is a certificate encoding. The public CA certificates must come from
the certificate authority that issued the transmitter's signing certificate.

| Environment variable | Contents | Required? |
| --- | --- | --- |
| `FE_XMLSEC_PATH` | Path to the executable installed above | Defaults to `xmlsec1` on PATH |
| `FE_TRUSTED_CERTIFICATES` | Public root CA certificates that this server trusts | Yes, at least one |
| `FE_INTERMEDIATE_CERTIFICATES` | Public intermediate CA certificates linking a signer to a trusted root | Needed when that chain has intermediates; this endpoint accepts only the leaf certificate in XML |
| `FE_CERTIFICATE_CRLS` | Current certificate revocation lists published by those CAs | Optional in this implementation |

Your local `.p12` certificate's issuer is **digifirma CA Subordinada 1**. Its root
and intermediate can be obtained from the official
[Digifirma Certificados Raíz / SubCA page](https://digi.camarasantodomingo.do/informacion-adicional/certificados-raiz/):

1. Download **DIGIFIRMA CA RAÍZ** for the trust anchor.
2. Download **DIGIFIRMA CA SUBORDINADA 1** for the intermediate.
3. Optionally download the current **CRL** for that intermediate. Do not select
   the legacy 2019 CRL for this chain.

Download the root and intermediate separately. Store them outside the repository,
for example in `/Users/your-user/.config/tigoo/fe-certs` on macOS or
`/etc/tigoo/fe-certs` on Ubuntu. Replace `your-user` with your actual login name.
Use one certificate per configured PEM path.

The issuer may supply `.crt` or `.cer` files. The extension does not tell you
whether the encoding is PEM or DER. If a file contains
`-----BEGIN CERTIFICATE-----`, normalize it as PEM:

```sh
openssl x509 -inform PEM -in downloaded-root.crt -out root-ca.pem
openssl x509 -inform PEM -in downloaded-intermediate.crt -out intermediate-ca.pem
```

If the downloaded certificates are binary DER instead, use:

```sh
openssl x509 -inform DER -in downloaded-root.crt -out root-ca.pem
openssl x509 -inform DER -in downloaded-intermediate.crt -out intermediate-ca.pem
```

Run these commands in the certificate directory, substituting the actual download
filenames. Inspect the public certificates and compare their SHA256 fingerprints
with values confirmed through the issuer's official publication/support channel:

```sh
openssl x509 -in root-ca.pem -noout -subject -issuer -dates -fingerprint -sha256
openssl x509 -in intermediate-ca.pem -noout -subject -issuer -dates -fingerprint -sha256
openssl verify -CAfile root-ca.pem intermediate-ca.pem
```

The last command checks the intermediate's chain; it does not independently
establish that the selected root is trustworthy. Never substitute the caller's
leaf certificate or a newly generated self-signed certificate for the CA root.

For an optional binary DER CRL download:

```sh
openssl crl -inform DER -in downloaded.crl -out current-crl.pem
openssl crl -in current-crl.pem -noout -issuer -lastupdate -nextupdate
openssl crl -in current-crl.pem -noout -verify -CAfile intermediate-ca.pem
```

If the downloaded CRL is already PEM, use `-inform PEM` in the conversion command.
Refresh configured CRLs before `nextUpdate`; do not invent a CRL file or configure
a nonexistent path. See the OpenSSL documentation for
[certificate conversion](https://docs.openssl.org/3.5/man1/openssl-x509/) and
[CRL processing](https://docs.openssl.org/3.5/man1/openssl-crl/).

Digifirma is the issuer of the local certificate, not a universal CA for every
transmitter. Add the independently verified root/intermediate chains for any other
issuers you intend to accept. If DGII sends a signed seed during certification,
obtain the CA chain for DGII's actual signing certificate through its certification
portal/support; do not assume it uses the local Digifirma chain.

### Configure the backend

Example for Ubuntu after obtaining the Digifirma files:

```sh
export FE_XMLSEC_PATH=/usr/bin/xmlsec1
export FE_TRUSTED_CERTIFICATES=/etc/tigoo/fe-certs/root-ca.pem
export FE_INTERMEDIATE_CERTIFICATES=/etc/tigoo/fe-certs/intermediate-ca.pem
export FE_CERTIFICATE_CRLS=
```

On macOS, use `/opt/homebrew/bin/xmlsec1` and the absolute paths to your downloaded
PEM files. Leave `FE_CERTIFICATE_CRLS` empty until you have a current, verified CRL;
then set it to that file's absolute path. The three certificate lists accept
comma-separated paths without spaces around the commas.

Set these variables in the environment of the Phoenix process (or its service
environment file) and restart the backend using your usual procedure. Editing an
example file alone does not configure a running process. The service account must
be able to read the PEM files and execute XMLSec.

The local launch scripts read `server/.env`, not `server/.env.example`. Copy only
the FE settings into your existing `.env`; preserve its other settings. If `.env`
does not exist yet, use `.env.example` as its starting point.

The certificate lists accept comma-separated PEM paths. Trusted CA files are
required and must come from an independently trusted source. Intermediates and
CRLs are optional; keep configured CRLs current. Automatic CRL fetching and OCSP
are not implemented. With no CRLs configured, revocation is not checked.
Missing XMLSec or trust files cause validation to return HTTP 503. The server does
not read `fe/credentials.txt` or use any `.p12` private key.

## Validation and response

The signed input must contain exactly `valor`, `fecha`, and one XMLDSig Signature
under `SemillaModel`. The bundled `priv/fe/Semilla.xsd` is copied unchanged from
DGII's `Semilla v.1.0.xsd`:

https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Paginas/documentacionSobreE-CF.aspx

Saxy checks the exact structure and resolves signature namespaces. OTP
`:xmerl_xsd` checks the seed envelope, using a Signature placeholder because the
schema's wildcard explicitly skips its contents. Only application-controlled
element names reach xmerl, avoiding atom creation from arbitrary uploaded tags.
XMLSec separately verifies the original uploaded XML, including the actual
Signature; no re-encoded document is used for cryptographic verification.

The signature profile requires RSA-SHA256, a SHA256 digest, exactly one Reference
with `URI=""`, and an enveloped-signature transform, optionally followed by C14N.
Inclusive C14N 1.0 and exclusive C14N without comments are supported. The document
must embed exactly one signing certificate. Supply intermediates through server
configuration. DTDs, external references, XPath/XSLT transforms, KeyValue keys,
multiple signatures, and uploads larger than 64 KiB are rejected.

The certificate's subject serialNumber attribute identifies its owner. XMLSec
checks its chain and validity dates against the configured trust store. The token
binds that subject identifier and the certificate's SHA256 fingerprint. This does
not establish DGII delegation or grant any tenant/admin permissions.

The former application-defined `version` field has been removed from GET output.
The transmitter's Signature supplies the third element required by the signed-seed
XSD. Keeping both version and Signature would exceed its cardinality.

Seeds expire after five minutes and are consumed atomically only after successful
verification. At most 10,000 pending seeds are held in memory. Restarting the
backend invalidates outstanding seeds. Multiple instances require sticky routing
for the seed exchange or replacing the store with shared storage.

Successful responses contain `token`, `expira`, and `expedido`, with dates formatted
as `YYYY-MM-DDTHH:mm:ssZ`. The token is a one-hour Phoenix signed token, separate
from tenant login tokens. Future protected FE endpoints must call
`TigooServer.FeAuthentication.verify_token/1` and apply authorization for the
authenticated certificate owner.

Malformed or invalid signatures return HTTP 400; unknown, expired, or already
consumed seeds return HTTP 401. Responses disable caching.

## Manual request

### Local walkthrough

Keep the backend running throughout this sequence. A restart clears pending seeds,
and each seed expires after five minutes. Use the same backend host for both curl
requests. The commands below assume the shell and IEx are in `server`.

1. In a terminal, save a fresh XML seed (no HTTP headers are written into the XML):

   ```sh
   cd /Users/beltre.wilton/apps/tigoo-app/server
   bash sh/test_fe_semilla.sh
   ```

2. In your already running IEx session, sign it using your local credentials file.
   Paste the entire `case` expression; it returns only the signing result, without
   printing the password or putting the password literal in command history:

   ```elixir
   case Regex.run(~r/^\s*Password\s*[:=]\s*(.+)$/mi, File.read!("../fe/credentials.txt")) do
     [_, password] ->
       TigooServer.Sign.sign_file(
         "semilla.xml",
         "signed-seed.xml",
         "../fe/22813977_identity.p12",
         password |> String.trim() |> String.trim("\"") |> String.trim("'")
       )
     _ -> {:error, :password_field_not_found}
   end
   ```

   Expected result: `:ok`. This walkthrough reads the `Password:` or `Password=`
   entry in your local credentials file; the signing module itself still receives
   the password explicitly. If signing returns an error, resolve it before POSTing
   so an older `signed-seed.xml` is not submitted accidentally.

3. Back in the terminal, submit the signed seed:

   ```sh
   bash sh/test_fe_validacioncertificado.sh
   ```

   Expected response: HTTP 200 with `token`, `expira`, and `expedido` in JSON.
   The seed is now consumed; request and sign another seed before another successful
   submission. Do not edit the signed XML.

For a different backend, supply its base URL to both scripts:

```sh
bash sh/test_fe_semilla.sh https://your-host
# Sign semilla.xml in IEx, then:
bash sh/test_fe_validacioncertificado.sh signed-seed.xml https://your-host
```

### Sign the seed in Elixir

`TigooServer.Sign` implements the signing profile from `../fe/Firmado de e-CF.pdf`.
It uses inclusive C14N 1.0 without comments, RSA-SHA256, a SHA256 digest, one
enveloped-signature transform, and an empty Reference URI covering the document.
The leaf certificate from the caller's `.p12` is embedded in X509Data. The signed
output is checked against that certificate's public key before being returned;
this checks signing consistency, not CA trust or revocation.

Newer XMLSec releases use strict key lookup. The signer detects support for
`--lax-key-search` from XMLSec's help and enables it for its single loaded private
key and pinned public-key consistency check. Older Ubuntu versions omit that
flag. This does not change the receiving endpoint's CA trust checks.

The module supports the roots `SemillaModel`, `ECF`, `ACECF`, `ARECF`, `ANECF`, and
`RFCE`. It removes inter-element formatting whitespace while retaining text values,
mixed content, and `xml:space="preserve"`. It rejects existing signatures, DTDs,
undeclared entities, processing instructions other than the XML declaration,
non-UTF-8 XML, and inputs larger than 5 MB. Input comments are omitted, consistent
with the no-comments signature profile. Only one RSA signing identity is accepted
per PKCS#12 file. Passwords containing NUL or line breaks are not supported.

Configure OpenSSL alongside XMLSec:

```ini
# Apple Silicon macOS
FE_OPENSSL_PATH=/opt/homebrew/opt/openssl@3/bin/openssl
# Ubuntu: use FE_OPENSSL_PATH=/usr/bin/openssl instead
```

The module does not load `.env` itself. `runtime.exs` reads `FE_OPENSSL_PATH` from
the process environment, just like `FE_XMLSEC_PATH`. Both paths can also be
overridden using the `:openssl_path` and `:xmlsec_path` function options.

Example calls in an already running application, from the `server` directory:

```elixir
# Return {:ok, signed_xml} or {:error, reason}.
TigooServer.Sign.sign(
  File.read!("semilla.xml"),
  "../fe/22813977_identity.p12",
  System.fetch_env!("FE_SIGN_PASSWORD")
)

# Write the exact signed bytes and return :ok or {:error, reason}.
TigooServer.Sign.sign_file(
  "semilla.xml",
  "signed-seed.xml",
  "../fe/22813977_identity.p12",
  System.fetch_env!("FE_SIGN_PASSWORD")
)
```

`FE_SIGN_PASSWORD` is an example secret supplied by the caller; the signing module
does not read it implicitly. Pass a password obtained from your secret provider in
production. Do not hardcode it or print it in IEx/logs. The local `credentials.txt`
is not read by this module.

The password reaches OpenSSL through stdin, not command arguments. The private key
is temporarily exported to a mode-0600 file inside a randomly named mode-0700
directory, and cleanup runs on success and failure. Forced process/OS termination
can leave temporary files behind; protect the signing host's temporary filesystem.
The signed XML contains the public certificate, never the private key.

Do not reformat, re-encode, or edit XML returned by this module. Sign an unsigned
seed from the running backend and submit it before its five-minute lifetime ends.
Keep `valor` and `fecha` exactly as returned, including their text whitespace:
formatting the unsigned XML can insert whitespace into a field and prevent it
from matching the original issued seed. The download script saves the raw body.
This signing module is a caller-side operation and is not invoked by the receiving
`validacioncertificado` endpoint.

### Submit the signed seed

With the backend already running, obtain and sign a fresh XML seed, then run:

```sh
bash sh/test_fe_validacioncertificado.sh signed-seed.xml https://your-host
```

Change the Accept header to `application/xml` for an XML response. Each seed can
be exchanged only once, so obtain a new signed seed for each successful request.
