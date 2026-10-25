defmodule TigooServer.FeSignature do
  @moduledoc false

  import Saxy.XML, only: [element: 3]
  require Record

  Record.defrecordp(:certificate, Record.extract(:OTPCertificate, from_lib: "public_key/include/public_key.hrl"))
  Record.defrecordp(:tbs_certificate, Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/public_key.hrl"))

  @ds "http://www.w3.org/2000/09/xmldsig#"
  @rsa "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
  @sha "http://www.w3.org/2001/04/xmlenc#sha256"
  @enveloped @ds <> "enveloped-signature"
  @c14n ["http://www.w3.org/TR/2001/REC-xml-c14n-20010315", "http://www.w3.org/2001/10/xml-exc-c14n#"]
  @max_bytes 65_536

  def verify(xml) when is_binary(xml) and byte_size(xml) <= @max_bytes do
    with true <- String.valid?(xml) and not String.contains?(xml, ["\0", "<!DOCTYPE", "<!ENTITY"]),
         {:ok, document} <- Saxy.SimpleForm.parse_string(xml),
         {:ok, seed, certificate} <- signed_seed(expand(document, %{})),
         :ok <- validate_schema(seed),
         {:ok, identity} <- certificate_identity(certificate),
         {:ok, executable, config} <- verifier_config(),
         :ok <- verify_signature(xml, executable, config) do
      {:ok, seed, identity}
    else
      {:error, :verifier_unavailable} = error -> error
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  def verify(_), do: {:error, :invalid_signature}

  @doc "Verifies the enveloped RSA-SHA256 signature and trusted certificate of an e-CF."
  def verify_ecf(xml) when is_binary(xml) and byte_size(xml) <= 5_000_000 do
    with true <- String.valid?(xml) and not String.contains?(xml, ["\0", "<!DOCTYPE", "<!ENTITY"]),
         {:ok, document} <- Saxy.SimpleForm.parse_string(xml,
           expand_entity: {TigooServer.Sign, :reject_entity, []}),
         {{"", "ECF"}, [], children} <- expand(document, %{}),
         signature when is_tuple(signature) <- List.last(elements(children)),
         {:ok, certificate} <- signature_profile(signature),
         {:ok, identity} <- certificate_identity(certificate),
         {:ok, executable, config} <- verifier_config(),
         :ok <- verify_signature(xml, executable, config) do
      {:ok, identity}
    else
      {:error, :verifier_unavailable} = error -> error
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  def verify_ecf(_), do: {:error, :invalid_signature}

  defp signed_seed({{"", "SemillaModel"}, [], children}) do
    with [{{"", "valor"}, [], [value]}, {{"", "fecha"}, [], [date]}, signature] <- elements(children),
         true <- is_binary(value) and is_binary(date),
         {:ok, _} <- Base.decode64(value),
         {:ok, certificate} <- signature_profile(signature) do
      {:ok, %{valor: value, fecha: date}, certificate}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp signed_seed(_), do: {:error, :invalid_signature}

  defp signature_profile({{@ds, "Signature"}, [], content}) do
    with [{{@ds, "SignedInfo"}, [], info}, {{@ds, "SignatureValue"}, [], [value]}, key_info] <- elements(content),
         true <- is_binary(value),
         {:ok, _} <- decode64(value),
         [{{@ds, "CanonicalizationMethod"}, [{"Algorithm", canonicalization}], []},
          {{@ds, "SignatureMethod"}, [{"Algorithm", @rsa}], []},
          {{@ds, "Reference"}, [{"URI", ""}], reference}] <- elements(info),
         true <- canonicalization in @c14n,
         [{{@ds, "Transforms"}, [], transforms},
          {{@ds, "DigestMethod"}, [{"Algorithm", @sha}], []},
          {{@ds, "DigestValue"}, [], [digest]}] <- elements(reference),
         true <- valid_transforms?(elements(transforms)),
         {:ok, hash} <- decode64(digest),
         true <- byte_size(hash) == 32,
         {{@ds, "KeyInfo"}, [], key_content} <- key_info,
         [{{@ds, "X509Data"}, [], x509}] <- elements(key_content),
         [{{@ds, "X509Certificate"}, [], [encoded]}] <- elements(x509),
         {:ok, certificate} <- decode64(encoded) do
      {:ok, certificate}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp signature_profile(_), do: {:error, :invalid_signature}

  defp valid_transforms?([{{@ds, "Transform"}, [{"Algorithm", @enveloped}], []}]), do: true

  defp valid_transforms?([
         {{@ds, "Transform"}, [{"Algorithm", @enveloped}], []},
         {{@ds, "Transform"}, [{"Algorithm", algorithm}], []}
       ]), do: algorithm in @c14n

  defp valid_transforms?(_), do: false

  defp decode64(text) when is_binary(text) do
    text |> String.replace(~r/\s+/, "") |> Base.decode64()
  end

  defp elements(content) do
    Enum.reject(content, fn node -> is_binary(node) and String.trim(node) == "" end)
  end

  # Resolve namespaces instead of relying on a particular ds: prefix. Keep
  # non-namespace attributes so the strict signature profile rejects them.
  defp expand({name, attrs, children}, inherited) do
    namespaces = Enum.reduce(attrs, inherited, fn
      {"xmlns", uri}, acc -> Map.put(acc, "", uri)
      {"xmlns:" <> prefix, uri}, acc -> Map.put(acc, prefix, uri)
      _, acc -> acc
    end)

    expanded_name = case String.split(name, ":", parts: 2) do
      [local] -> {Map.get(namespaces, "", ""), local}
      [prefix, local] -> {Map.fetch!(namespaces, prefix), local}
    end

    attrs = Enum.reject(attrs, fn {key, _} -> key == "xmlns" or String.starts_with?(key, "xmlns:") end)
    children = Enum.map(children, fn
      {_, _, _} = child -> expand(child, namespaces)
      text -> text
    end)

    {expanded_name, attrs, children}
  end

  defp validate_schema(seed) do
    # xmerl owns per-validation ETS tables. A short-lived process releases them
    # even when schema validation fails or the HTTP connection stays alive.
    task = Task.Supervisor.async_nolink(TigooServer.TaskSupervisor, fn ->
      try do
        validate_schema_envelope(seed)
      rescue
        _ -> {:error, :invalid_signature}
      catch
        :exit, _ -> {:error, :invalid_signature}
      end
    end)

    case Task.yield(task, 5000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :verifier_unavailable}
    end
  end

  defp validate_schema_envelope(seed) do
    schema = Application.app_dir(:tigoo_server, "priv/fe/Semilla.xsd")

    if File.regular?(schema) do
      # Saxy already checked the exact envelope and Signature position. The XSD
      # skips Signature contents, so validate an equivalent envelope with a
      # placeholder. Only fixed names reach xmerl, avoiding untrusted atom creation.
      document = element("SemillaModel", [], [
        element("valor", [], Saxy.XML.characters(seed.valor)),
        element("fecha", [], Saxy.XML.characters(seed.fecha)),
        element("Signature", [{"xmlns", @ds}], [])
      ]) |> Saxy.encode!()

      {parsed, []} = :xmerl_scan.string(String.to_charlist(document), quiet: true)

      case :xmerl_xsd.process_validate(String.to_charlist(schema), parsed) do
        {:error, _} -> {:error, :invalid_signature}
        {_validated, _state} -> :ok
      end
    else
      {:error, :verifier_unavailable}
    end
  end

  defp certificate_identity(der) do
    cert = :public_key.pkix_decode_cert(der, :otp)
    tbs = certificate(cert, :tbsCertificate)
    {:rdnSequence, rdns} = tbs_certificate(tbs, :subject)

    serials = for rdn <- rdns,
                  {:AttributeTypeAndValue, {2, 5, 4, 5}, value} <- rdn,
                  do: attribute_text(value)

    case serials do
      [subject_id] when is_binary(subject_id) and byte_size(subject_id) > 0 ->
        fingerprint = :crypto.hash(:sha256, der) |> Base.encode16(case: :lower)
        {:ok, %{subject_id: subject_id, certificate_sha256: fingerprint}}

      _ -> {:error, :invalid_signature}
    end
  end

  defp attribute_text({_encoding, text}) when is_binary(text), do: text
  defp attribute_text({_encoding, text}) when is_list(text), do: List.to_string(text)
  defp attribute_text(text) when is_binary(text), do: text
  defp attribute_text(text) when is_list(text), do: List.to_string(text)
  defp attribute_text(_), do: nil

  defp verifier_config do
    config = Application.get_env(:tigoo_server, :fe_authentication, [])
    executable = System.find_executable(Keyword.get(config, :xmlsec_path, "xmlsec1"))
    roots = Keyword.get(config, :trusted_certificates, [])
    files = roots ++ Keyword.get(config, :intermediate_certificates, []) ++ Keyword.get(config, :crls, [])

    if executable && roots != [] && Enum.all?(files, &File.regular?/1) do
      {:ok, executable, config}
    else
      {:error, :verifier_unavailable}
    end
  end

  defp verify_signature(xml, executable, config) do
    directory = Path.join(System.tmp_dir!(), "tigoo-fe-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false))

    with :ok <- File.mkdir(directory) do
      try do
        File.chmod!(directory, 0o700)
        path = Path.join(directory, "seed.xml")
        File.write!(path, xml)

        args = ["--verify", "--crypto", "openssl", "--crypto-config", directory,
          "--enabled-reference-uris", "empty", "--enabled-key-data", "x509"] ++
          certificate_args(config, :trusted_certificates, "--trusted-pem") ++
          certificate_args(config, :intermediate_certificates, "--untrusted-pem") ++
          certificate_args(config, :crls, "--crl-pem") ++ [path]

        port = Port.open({:spawn_executable, executable}, [
          :binary, :exit_status, :stderr_to_stdout, :use_stdio,
          args: args
        ])

        await_verification(port, System.monotonic_time(:millisecond) + 10_000)
      after
        File.rm_rf(directory)
      end
    else
      _ -> {:error, :verifier_unavailable}
    end
  end

  defp certificate_args(config, key, flag) do
    config |> Keyword.get(key, []) |> Enum.flat_map(&[flag, &1])
  end

  defp await_verification(port, deadline) do
    receive do
      {^port, {:data, _output}} -> await_verification(port, deadline)
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, _}} -> {:error, :invalid_signature}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Port.close(port)
        {:error, :verifier_unavailable}
    end
  end
end
