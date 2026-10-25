defmodule TigooServer.Fe.Client.CLI do
  @moduledoc "Command-line adapter for DGII manifest submission or a track-ID query."
  alias TigooServer.Fe.{Client, Submission}

  def main(argv) do
    {arguments, rest, invalid} = OptionParser.parse(argv, strict: [
      batch: :string, report: :string, track_id: :string, environment: :string,
      issuer_rnc: :string, p12: :string, credentials: :string, poll_attempts: :integer,
      poll_interval: :integer, receive_timeout: :integer, schema_dir: :string,
      xmlsec: :string, openssl: :string, xmllint: :string, help: :boolean
    ])
    cond do
      invalid != [] or rest != [] ->
        IO.puts(:stderr, "Unknown or invalid arguments. Use --help.")
        2
      arguments[:track_id] && (arguments[:batch] || arguments[:report]) ->
        IO.puts(:stderr, "Use either --track-id or batch submission options.")
        2
      arguments[:help] ->
        IO.puts(help())
        0
      true -> run(arguments)
    end
  rescue
    error in [ArgumentError, KeyError, File.Error, TigooServer.Fe.Client.Error] ->
      IO.puts(:stderr, Exception.message(error))
      1
    _ ->
      IO.puts(:stderr, "DGII client stopped unexpectedly; inspect the submission journal before retrying.")
      1
  end

  defp run(arguments) do
    caller = System.get_env("TIGOO_FE_CALLER_DIR") || File.cwd!()
    root = System.get_env("TIGOO_FE_REPO_ROOT") || Path.expand("..", File.cwd!())
    arguments = Enum.map(arguments, fn {key, value} ->
      cond do
        key in [:batch, :report, :p12, :credentials, :schema_dir] -> {key, Path.expand(value, caller)}
        key in [:xmlsec, :openssl, :xmllint] and String.contains?(value, "/") -> {key, Path.expand(value, caller)}
        true -> {key, value}
      end
    end)
    options = [
      environment: Keyword.get(arguments, :environment, "certecf"),
      issuer_rnc: Keyword.get(arguments, :issuer_rnc, "131362702"),
      p12_path: Keyword.get(arguments, :p12, Path.join(root, "p12_companies/ans/22813977_identity.p12")),
      credentials_file: Keyword.get(arguments, :credentials, Path.join(root, "p12_companies/ans/credentials.txt")),
      receive_timeout: Keyword.get(arguments, :receive_timeout, 60_000)
    ]
    options = Enum.reduce([xmlsec: :xmlsec_path, openssl: :openssl_path], options, fn {flag, key}, opts ->
      if value = arguments[flag], do: Keyword.put(opts, key, value), else: opts
    end)
    client = Client.new(options)
    if track = arguments[:track_id] do
      case Client.result(client, track) do
        {:ok, body, _client} ->
          IO.puts(Jason.encode!(body, pretty: true))
          0
        {:error, error} ->
          IO.puts(:stderr, Exception.message(error))
          1
      end
    else
      batch = Keyword.get(arguments, :batch, Path.join(root, "fe/data-test/generated/131362702-25102026004903"))
      options = [expected_document_type: "ECF", poll_attempts: Keyword.get(arguments, :poll_attempts, 20),
        poll_interval: Keyword.get(arguments, :poll_interval, 1000),
        on_result: fn encf, state, _body -> IO.puts("#{encf}: #{state}") end]
      options = Enum.reduce([report: :report, schema_dir: :schema_directory, xmllint: :xmllint_path], options, fn {flag, key}, opts ->
        if value = arguments[flag], do: Keyword.put(opts, key, value), else: opts
      end)
      IO.puts("DGII environment: #{client.environment}; issuer RNC: #{client.issuer_rnc}")
      case Submission.run(batch, client, options) do
        {:ok, report} ->
          IO.puts("All #{map_size(report["entries"])} submissions accepted. Journal: #{report["report_path"]}")
          IO.puts("Full low-amount ECFs for portal upload: #{length(report["portal_uploads"])}. See the journal file list.")
          0
        {:error, error, report} ->
          IO.puts(:stderr, Exception.message(error))
          if report, do: IO.puts(:stderr, "Journal: #{report["report_path"]}")
          1
      end
    end
  end

  defp help do
    """
    Usage: bash server/sh/submit_fe_certification.sh [options]

    --batch DIRECTORY       Generated batch containing manifest.json
    --report PATH           Resumable journal (default <batch>/submission-<environment>.json)
    --track-id ID           Query one existing ECF track ID instead of posting a batch
    --environment NAME      certecf (default), testecf or ecf
    --issuer-rnc RNC        Authorized issuer (default 131362702)
    --p12 PATH              Signing identity (default repo p12_companies/ans identity)
    --credentials PATH      Credentials file containing one Password field
    --poll-attempts COUNT   Maximum queries per ECF per run (default 20)
    --poll-interval MS      Delay between queries, 0..60000 (default 1000)
    --receive-timeout MS    HTTP receive timeout (default 60000)
    --schema-dir DIRECTORY  Runtime XSD registry override
    --xmlsec PATH           xmlsec1 executable for seed signing
    --openssl PATH          OpenSSL executable for seed signing
    --xmllint PATH          xmllint executable for preflight validation
    --help

    Relative paths resolve from the caller's original directory. Running this
    command submits fiscal documents to the selected DGII environment. It never
    compiles, generates, re-signs or reformats invoice documents. It starts only
    HTTP/crypto dependencies, not Phoenix/Repo. Modules must already be built.
    """
  end
end
