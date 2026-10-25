defmodule TigooServer.Fe.Generation.Artifact do
  @moduledoc "Shared native-tool configuration and signed XML artifact validation."
  alias TigooServer.Fe.Generation.{Command, Error, Schema}

  def options(opts) do
    config = Application.get_env(:tigoo_server, :fe_authentication, [])
    Enum.reduce([xmlsec_path: "xmlsec1", openssl_path: "openssl", xmllint_path: "xmllint",
      trusted_certificates: [], intermediate_certificates: [], crls: []], opts, fn {key, default}, acc ->
      Keyword.put_new(acc, key, Keyword.get(config, key, default))
    end)
  end

  def validate_options!(opts) do
    Enum.each([:xmlsec_path, :openssl_path, :xmllint_path], fn key ->
      unless System.find_executable(opts[key]), do: Error.fail!(:dependency, "Executable unavailable: #{opts[key]}")
    end)
    roots = opts[:trusted_certificates]
    if roots == [], do: Error.fail!(:options, "Trusted CA certificates are required for signed batch generation")
    Enum.each(roots ++ opts[:intermediate_certificates] ++ opts[:crls], fn path ->
      unless File.regular?(path), do: Error.fail!(:options, "Certificate-chain file is unavailable: #{path}")
    end)
    :ok
  end

  def save_verified!(xml, path, schema, opts) do
    File.write!(path, xml, [:exclusive])
    verify_file!(path, schema, opts)
    if sha256(File.read!(path)) != sha256(xml), do: Error.fail!(:verification, "Signed bytes changed during export")
    :ok
  end

  def verify_file!(path, schema, opts) do
    Schema.validate_file!(path, schema, opts)
    certificate_args = Enum.flat_map([
      {:trusted_certificates, "--trusted-pem"}, {:intermediate_certificates, "--untrusted-pem"}, {:crls, "--crl-pem"}
    ], fn {key, flag} -> Enum.flat_map(opts[key], &[flag, &1]) end)
    Command.run!(opts[:xmlsec_path], ["--verify", "--crypto", "openssl", "--crypto-config", Path.dirname(path),
      "--enabled-reference-uris", "empty", "--enabled-key-data", "x509"] ++ certificate_args ++ [path])
    :ok
  end

  def sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
