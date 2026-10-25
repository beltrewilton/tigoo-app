defmodule TigooServer.Sign do
  @moduledoc """
  Signs UTF-8 electronic invoicing XML using a password-protected PKCS#12 identity.

  Follows DGII's Firmado de e-CF profile: inclusive C14N 1.0 without comments,
  RSA-SHA256, SHA256 digest, an empty Reference URI, and an enveloped Signature
  appended to the document root with the leaf X509Certificate embedded.

  Returns the XMLSec output unchanged. Do not format or otherwise modify it after
  signing. This module does not establish certificate trust or DGII authorization.

  The password is supplied to OpenSSL over stdin, never as a command argument.
  An unencrypted private key exists briefly in a mode-0600 file inside a mode-0700
  temporary directory, removed in an `after` block. Forced OS/process termination
  can prevent cleanup; use a protected temporary filesystem on signing hosts.
  """

  import Saxy.XML, only: [element: 3, characters: 1]

  @ds "http://www.w3.org/2000/09/xmldsig#"
  @c14n "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"
  @rsa "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
  @sha "http://www.w3.org/2001/04/xmlenc#sha256"
  @roots ~w(SemillaModel ECF ACECF ARECF ANECF RFCE)
  @max_bytes 5_000_000

  @type reason :: :invalid_xml | :already_signed | :invalid_password |
          :certificate_unavailable | :dependency_unavailable | :pkcs12_read_failed |
          :signing_failed | :command_timeout | :file_error

  @doc """
  Signs an XML binary with the identity at `p12_path`.

  Options `:xmlsec_path` and `:openssl_path` override the executable paths configured
  under `:tigoo_server, :fe_authentication`. No certificate path or password is
  read implicitly from the repository or credentials.txt.
  """
  @spec sign(binary(), Path.t(), binary(), keyword()) :: {:ok, binary()} | {:error, reason()}
  def sign(xml, p12_path, password, opts \\ [])

  def sign(xml, p12_path, password, opts)
      when is_binary(xml) and is_binary(p12_path) and is_binary(password) and is_list(opts) do
    with :ok <- valid_password(password),
         true <- File.regular?(p12_path),
         {:ok, template} <- template(xml),
         {:ok, xmlsec} <- executable(opts, :xmlsec_path, "xmlsec1"),
         {:ok, openssl} <- executable(opts, :openssl_path, "openssl") do
      sign_in_directory(template, Path.expand(p12_path), password, xmlsec, openssl)
    else
      false -> {:error, :certificate_unavailable}
      error -> error
    end
  rescue
    _ -> {:error, :signing_failed}
  end

  def sign(_, _, _, _), do: {:error, :invalid_xml}

  @doc "Reads XML, signs it, and writes the unchanged signed bytes to output_path."
  @spec sign_file(Path.t(), Path.t(), Path.t(), binary(), keyword()) :: :ok | {:error, reason()}
  def sign_file(input_path, output_path, p12_path, password, opts \\ []) do
    with {:ok, %{size: size}} when size <= @max_bytes <- File.stat(input_path),
         {:ok, xml} <- File.read(input_path),
         {:ok, signed} <- sign(xml, p12_path, password, opts),
         :ok <- File.write(output_path, signed) do
      :ok
    else
      {:ok, _stat} -> {:error, :invalid_xml}
      {:error, reason} when reason in [:enoent, :eacces, :eisdir, :enotdir, :enospc, :erofs] ->
        {:error, :file_error}
      error -> error
    end
  end

  defp valid_password(password) do
    if String.contains?(password, ["\0", "\r", "\n"]),
      do: {:error, :invalid_password},
      else: :ok
  end

  defp template(xml) when byte_size(xml) <= @max_bytes do
    with true <- String.valid?(xml) and not String.contains?(xml, ["\0", "<!DOCTYPE", "<!ENTITY"]),
         # SimpleForm drops processing instructions. Reject them instead of
         # silently changing a document that contains meaningful instructions.
         false <- Regex.match?(~r/<\?(?!xml\s)/, xml),
         {:ok, {name, attrs, children} = root} <-
           Saxy.SimpleForm.parse_string(xml,
             cdata_as_characters: false,
             expand_entity: {__MODULE__, :reject_entity, []}),
         true <- local_name(name) in @roots,
         :ok <- unsigned(root) do
      {^name, ^attrs, children} = prepare({name, attrs, children}, false)
      document = element(name, attrs, children ++ [signature_template()])

      encoded = Saxy.encode!(document, version: "1.0", encoding: "UTF-8")

      # Saxy escapes markup, but literal attribute tabs/newlines would otherwise
      # be normalized by the next XML parser. Preserve decoded character values.
      encoded = Regex.replace(~r/"[^"]*"/, encoded, fn attribute ->
        attribute |> String.replace("\t", "&#x9;") |> String.replace("\n", "&#xA;")
      end)

      {:ok, String.replace(encoded, "\r", "&#xD;")}
    else
      {:error, :already_signed} -> {:error, :already_signed}
      {:error, _} -> {:error, :invalid_xml}
      _ -> {:error, :invalid_xml}
    end
  rescue
    _ -> {:error, :invalid_xml}
  end

  defp template(_), do: {:error, :invalid_xml}

  @doc false
  def reject_entity(_name), do: raise(ArgumentError, "Undeclared XML entity")

  defp signed?({name, _attrs, children}) do
    local_name(name) == "Signature" or Enum.any?(children, fn
      {_, _, _} = child -> signed?(child)
      _ -> false
    end)
  end

  defp unsigned(root) do
    if signed?(root), do: {:error, :already_signed}, else: :ok
  end

  defp local_name(name), do: name |> String.split(":") |> List.last()

  defp prepare({name, attrs, children}, inherited_preserve) do
    preserve = case List.keyfind(attrs, "xml:space", 0) do
      {_, "preserve"} -> true
      {_, "default"} -> false
      _ -> inherited_preserve
    end

    has_elements = Enum.any?(children, &match?({_, _, _}, &1))
    has_text = Enum.any?(children, fn
      text when is_binary(text) -> String.trim(text) != ""
      {:cdata, _} -> true
      _ -> false
    end)

    children = Enum.flat_map(children, fn
      {_, _, _} = child -> [prepare(child, preserve)]
      {:cdata, text} -> [characters(text)]
      text when is_binary(text) ->
        if not preserve and has_elements and not has_text and String.trim(text) == "",
          do: [],
          else: [characters(text)]
    end)

    element(name, attrs, children)
  end

  defp signature_template do
    element("Signature", [{"xmlns", @ds}], [
      element("SignedInfo", [], [
        element("CanonicalizationMethod", [{"Algorithm", @c14n}], []),
        element("SignatureMethod", [{"Algorithm", @rsa}], []),
        element("Reference", [{"URI", ""}], [
          element("Transforms", [], [
            element("Transform", [{"Algorithm", @ds <> "enveloped-signature"}], [])
          ]),
          element("DigestMethod", [{"Algorithm", @sha}], []),
          element("DigestValue", [], [])
        ])
      ]),
      element("SignatureValue", [], []),
      element("KeyInfo", [], [
        element("X509Data", [], [element("X509Certificate", [], [])])
      ])
    ])
  end

  defp executable(opts, key, default) do
    config = Application.get_env(:tigoo_server, :fe_authentication, [])
    path = Keyword.get(opts, key, Keyword.get(config, key, default))

    case System.find_executable(path) do
      nil -> {:error, :dependency_unavailable}
      executable -> {:ok, executable}
    end
  end

  defp sign_in_directory(template, p12_path, password, xmlsec, openssl) do
    directory = Path.join(System.tmp_dir!(), "tigoo-sign-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false))
    key_search_args = key_search_args(xmlsec)

    case File.mkdir(directory) do
      :ok ->
        try do
          File.chmod!(directory, 0o700)
          Enum.each(["key.pem", "certificate.pem"], fn name ->
            path = Path.join(directory, name)
            File.write!(path, "", [:exclusive])
            File.chmod!(path, 0o600)
          end)
          File.write!(Path.join(directory, "template.xml"), template)

          key_args = ["pkcs12", "-in", p12_path, "-passin", "stdin", "-nocerts", "-nodes", "-out", "key.pem"]
          cert_args = ["pkcs12", "-in", p12_path, "-passin", "stdin", "-clcerts", "-nokeys", "-out", "certificate.pem"]
          sign_args = ["--sign", "--crypto", "openssl", "--enabled-reference-uris", "empty",
            "--privkey-pem", "key.pem,certificate.pem",
            "--output", "signed.xml"] ++ key_search_args ++ ["template.xml"]
          verify_args = ["--verify", "--crypto", "openssl", "--enabled-reference-uris", "empty",
            "--enabled-key-data", "raw-x509-cert", "--pubkey-cert-pem", "certificate.pem"] ++
            key_search_args ++ ["signed.xml"]

          with :ok <- command(openssl, key_args, directory, password <> "\n", :pkcs12_read_failed),
               :ok <- command(openssl, cert_args, directory, password <> "\n", :pkcs12_read_failed),
               :ok <- single_identity(directory),
               :ok <- command(xmlsec, sign_args, directory, nil, :signing_failed),
               :ok <- command(xmlsec, verify_args, directory, nil, :signing_failed),
               {:ok, signed} <- File.read(Path.join(directory, "signed.xml")) do
            {:ok, signed}
          else
            {:error, reason} when reason in [:pkcs12_read_failed, :signing_failed, :command_timeout] ->
              {:error, reason}
            _ -> {:error, :file_error}
          end
        after
          File.rm_rf(directory)
        end

      _ -> {:error, :file_error}
    end
  end

  defp key_search_args(xmlsec) do
    {help, 0} = System.cmd(xmlsec, ["--help-sign"], stderr_to_stdout: true)

    # Newer XMLSec versions require explicit permission to select an unnamed
    # key. Only one private key (or pinned verification certificate) is loaded
    # here. This does not disable certificate trust checks in the POST verifier.
    # Older Ubuntu packages already use this lookup and do not expose the flag.
    if String.contains?(help, "--lax-key-search"), do: ["--lax-key-search"], else: []
  end

  defp single_identity(directory) do
    keys = directory |> Path.join("key.pem") |> File.read!() |> :public_key.pem_decode()
    certs = directory |> Path.join("certificate.pem") |> File.read!() |> :public_key.pem_decode()

    case {keys, certs} do
      {[{kind, _, :not_encrypted}], [{:Certificate, _, :not_encrypted}]}
          when kind in [:PrivateKeyInfo, :RSAPrivateKey] -> :ok
      _ -> {:error, :pkcs12_read_failed}
    end
  end

  defp command(executable, args, directory, input, failure) do
    port = Port.open({:spawn_executable, executable}, [
      :binary, :exit_status, :stderr_to_stdout, :use_stdio,
      args: args, cd: directory
    ])

    if input, do: Port.command(port, input)
    await_command(port, System.monotonic_time(:millisecond) + 15_000, failure)
  end

  defp await_command(port, deadline, failure) do
    receive do
      {^port, {:data, _output}} -> await_command(port, deadline, failure)
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, _}} -> {:error, failure}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Port.close(port)
        {:error, :command_timeout}
    end
  end
end
