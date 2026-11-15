defmodule TigooServer.Fe.Certification do
  @moduledoc "Tenant-scoped adapter for the existing certification submission CLI flow."
  import Ecto.Query
  alias TigooServer.{Accounts.Company, Accounts.Scope, Repo, Tenants}
  alias TigooServer.Fe.{Client, Credentials, Generation, Submission}

  def batches(scope) do
    with {:ok, issuer} <- issuer(scope),
         {:ok, names} <- File.ls(root()) do
      batches = names
        |> Enum.sort()
        |> Enum.flat_map(fn name ->
          case read_batch(name, issuer) do
            {:ok, batch} -> [batch]
            _ -> []
          end
        end)
      {:ok, batches}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      _ -> {:error, "No se encontró la carpeta de casos de certificación generados."}
    end
  rescue
    _ -> {:error, "No se pudieron cargar los casos de certificación de esta empresa."}
  end

  def generate(scope, workbook, on_document) when is_binary(workbook) and byte_size(workbook) in 1..20_000_000 do
    with {:ok, issuer} <- issuer(scope),
         {:ok, identity} <- Credentials.for_tenant(scope.tenant) do
      id = scope.tenant <> "-" <> Integer.to_string(System.system_time(:millisecond)) <>
        "-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
      source_directory = Path.join([root(), ".sources", scope.tenant])
      source = Path.join(source_directory, id <> ".xlsx")
      output = Path.join(root(), id)
      try do
        File.mkdir_p!(source_directory)
        File.write!(source, workbook, [:exclusive])
        File.chmod!(source, 0o600)
        project = Path.expand("../../../..", __DIR__)
        trust = Application.get_env(:tigoo_server, :fe_authentication, [])
          |> Keyword.take([:trusted_certificates, :intermediate_certificates, :crls])
          |> Keyword.put_new(:trusted_certificates, [Path.join(project, "fe/digifirma-ca-raiz.crt")])
          |> Keyword.put_new(:intermediate_certificates, [Path.join(project, "fe/digifirma-ca-subordinada-1.crt")])
        opts = [workbook: source, output: output, issuer_rnc: issuer,
          p12_path: identity.p12_path, password: identity.password,
          strict_arithmetic: false, on_document: on_document] ++ trust

        case Generation.generate(opts) do
          {:ok, manifest} ->
            observations = Enum.reduce(manifest.documents, 0,
              &(length(&1.source_arithmetic_observations) + &2))
            {:ok, %{id: id, counts: manifest.counts, observations: observations}}
          {:error, error} -> {:error, Exception.message(error)}
        end
      after
        # Keep source provenance for published batches; discard unsuccessful uploads.
        unless File.regular?(Path.join(output, "manifest.json")), do: File.rm(source)
      end
    else
      {:error, message} when is_binary(message) -> {:error, message}
      _ -> {:error, "Configura el certificado y las credenciales de esta empresa en el paso 0."}
    end
  rescue
    _ -> {:error, "No se pudo generar el lote. Revisa el archivo XLSX y los permisos de almacenamiento."}
  end

  def generate(_, _, _), do: {:error, "Selecciona un archivo XLSX de máximo 20 MB."}

  def submit(scope, id, on_result) do
    with {:ok, issuer} <- issuer(scope),
         {:ok, batch} <- read_batch(id, issuer),
         true <- is_nil(batch.journal_error),
         {:ok, identity} <- Credentials.for_tenant(scope.tenant) do
      # Same options as submit_fe_certification.sh; the environment is fixed here.
      client = Client.new(environment: "certecf", issuer_rnc: issuer,
        p12_path: identity.p12_path, password: identity.password, receive_timeout: 60_000)

      case Submission.run(Path.join(root(), id), client,
             expected_document_type: "ECF", poll_attempts: 20, poll_interval: 1000,
             on_result: on_result) do
        {:ok, _report} -> :ok
        {:error, error, _report} -> {:error, Exception.message(error)}
      end
    else
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, :signing_identity_unavailable} -> {:error, "Configura el certificado de esta empresa en el paso 0."}
      _ -> {:error, "El lote o su registro de envíos no es válido para esta empresa."}
    end
  rescue
    _ -> {:error, "El envío se interrumpió. Revisa el registro de resultados antes de continuar."}
  end

  @doc "Returns an unchanged, checksum-verified full ECF for manual portal upload."
  def portal_document(scope, id, encf) do
    with {:ok, issuer} <- issuer(scope),
         {:ok, batch} <- read_batch(id, issuer),
         row when not is_nil(row) <- Enum.find(batch.rows, &(&1.encf == encf and not is_nil(&1.portal_file))),
         directory <- Path.expand(Path.join(root(), id)),
         path <- Path.expand(row.portal_file, directory),
         true <- String.starts_with?(path, directory <> "/"),
         true <- Path.basename(path) == issuer <> encf <> ".xml",
         {:ok, %{size: size}} when size <= 5_000_000 <- File.stat(path),
         {:ok, xml} <- File.read(path),
         true <- sha256(xml) == row.portal_sha256 do
      {:ok, %{xml: xml, filename: Path.basename(path)}}
    else
      _ -> {:error, :document_unavailable}
    end
  rescue
    _ -> {:error, :document_unavailable}
  end

  defp issuer(scope) do
    with true <- Scope.allowed?(scope, "company.settings") and Tenants.valid_identifier?(scope.tenant),
         [company] <- Repo.all(from(c in Company, where: c.active == true, limit: 2), prefix: scope.tenant),
         rnc when is_binary(rnc) <- company.rnc,
         rnc <- String.trim(rnc),
         true <- Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, rnc) do
      {:ok, rnc}
    else
      _ -> {:error, "Se requiere acceso a configuración y una única empresa activa con RNC válido."}
    end
  end

  defp read_batch(id, issuer) when is_binary(id) do
    with true <- id not in ["", ".", ".."] and Path.basename(id) == id,
         path <- Path.join([root(), id, "manifest.json"]),
         {:ok, bytes} <- File.read(path),
         {:ok, manifest} when is_map(manifest) <- Jason.decode(bytes),
         true <- manifest["authorized_issuer_rnc"] == issuer and manifest["worksheet"] == "ECF" and
           Map.get(manifest, "document_type", "ECF") == "ECF" and manifest["purpose"] in [nil, "dgii_data_tests"],
         documents when is_list(documents) and documents != [] <- manifest["documents"] do
      {report, journal_error} = read_report(id, issuer, bytes)
      entries = Map.get(report, "entries", %{})
      rows = Enum.map(documents, fn doc ->
        entry = Map.get(entries, doc["encf"], %{})
        %{encf: doc["encf"], type: doc["type"], amount: doc["amount_dop"],
          channel: if(doc["small_consumption"], do: "RFCE", else: "ECF"),
          portal_file: if(doc["small_consumption"] and doc["type"] == "32" and
            Decimal.compare(Decimal.new(doc["amount_dop"]), Decimal.new("250000")) == :lt, do: doc["ecf_file"]),
          portal_sha256: doc["ecf_sha256"],
          state: Map.get(entry, "state", "not_sent"), track_id: entry["track_id"],
          response: entry["result"] || entry["error"] || entry["query_error"] || entry["upload_response"]}
      end)
      {:ok, %{id: id, issuer: issuer, rows: rows, count: length(rows),
        accepted: Enum.count(rows, &(&1.state in ["accepted", "accepted_conditional"])),
        portal_count: Enum.count(documents, & &1["small_consumption"]),
        status: report["status"], last_error: get_in(report, ["last_error", "message"]),
        journal_error: journal_error}}
    else
      _ -> {:error, :batch_unavailable}
    end
  rescue
    _ -> {:error, :batch_unavailable}
  end

  defp read_batch(_, _), do: {:error, :batch_unavailable}

  defp read_report(id, issuer, manifest) do
    path = Path.join([root(), id, "submission-certecf.json"])
    case File.read(path) do
      {:error, :enoent} -> {%{}, nil}
      {:ok, bytes} ->
        with {:ok, report} when is_map(report) <- Jason.decode(bytes),
             true <- report["environment"] == "certecf" and report["issuer_rnc"] == issuer and
               report["manifest_sha256"] == sha256(manifest) and is_map(report["entries"]) do
          {report, nil}
        else
          _ -> {%{}, "El registro de envíos no corresponde a este lote de certificación. Revisa el archivo antes de continuar."}
        end
      _ -> {%{}, "No se pudo leer el registro de envíos guardado."}
    end
  end

  defp root do
    Application.get_env(:tigoo_server, :fe_certification_batch_directory,
      Path.expand("../../../../fe/data-test/generated", __DIR__))
  end
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
