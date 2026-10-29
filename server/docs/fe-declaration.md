# DGII declaration signing

`TigooServer.Fe.Declaration` signs Step 13 declarations without database access
or submission to DGII. Each invocation resolves credentials through
`Fe.Credentials.for_tenant/1`, using the configured `:fe_receivers_directory`
and that tenant's `.p12` and `credentials.txt`. No company or identity is hardcoded.

For application integration:

```elixir
TigooServer.Fe.Declaration.sign(tenant, unsigned_xml)
# {:ok, signed_xml} | {:error, reason}

TigooServer.Fe.Declaration.sign_file(tenant, input_path, output_path)
# :ok | {:error, reason}; an existing output is never overwritten
```

The caller must obtain the tenant from its authenticated scope. The module does
not authorize users or upload declarations on their behalf.

From the repository root, after the updated modules are built in the normal
deployment process:

```bash
bash server/sh/sign_fe_declaracion_jurada.sh ans \
  fe/declaracion_jurada/202610284618403.xml \
  fe/declaracion_jurada/202610284618403.elixir.signed.xml
```

The launcher uses `mix run --no-compile --no-start`; it does not start the web
server or repository. `ENV_FILE` selects the server environment file (default
`.env`). Input/output paths are relative to the directory where it is invoked.

Signing uses the shared `TigooServer.Sign` implementation: formatting whitespace
is removed before signing, declaration text is preserved, RSA-SHA256/SHA256 is
used, and the resulting signature is verified against the selected certificate.
OpenSSL and XMLSec remain native dependencies; Python and xmllint are not needed
for this operation. Temporary private-key files are cleaned up after signing.
Never format or otherwise modify the returned signed XML.

To build the updated Elixir modules, generate a new declaration, and compare it
byte-for-byte with the accepted compact file, run from the repository root:

```bash
bash server/sh/compare_fe_declaracion_jurada.sh ans
```

This comparison launcher explicitly runs `mix compile` when you execute it, then
calls the Elixir signing launcher. It runs no tests, formatting, database tasks,
or HTTP submissions. Optional arguments are input, reference, and new output
paths. Existing output files are never overwritten. Exit status is zero only
when the generated and reference files are identical; differing files remain
available for inspection.
