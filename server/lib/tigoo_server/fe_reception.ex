defmodule TigooServer.FeReception do
  @moduledoc "Receives signed e-CFs and returns a signed ARECF acknowledgement."

  import Ecto.Query
  import Saxy.XML, only: [element: 3, characters: 1]
  require Logger

  alias TigooServer.{FeReceivedEcf, FeSignature, FeXml, Repo, Sign, Tenants}
  alias TigooServer.Accounts.Company

  def receive_ecf(tenant, xml, identity) do
    prefix = Triplex.to_prefix(tenant)

    with {:ok, receiver} <- receiver(tenant, prefix) |> log_failure(:receiver_configuration),
         {:ok, document, invoice} <- FeXml.parse(xml) do
      case check_invoice(document, invoice, xml, identity, receiver, prefix) do
        :ok -> accept(invoice, xml, identity, receiver, prefix)
        {:reject, reason} -> receipt(invoice, receiver, reason)
        error -> error
      end
    end
  rescue
    # A missing migration, database outage or unavailable signing key must never
    # produce an acknowledgement claiming the invoice has been received.
    exception ->
      database_error = case exception do
        %Postgrex.Error{postgres: %{code: code}} -> " database_error=#{code}"
        _ -> ""
      end

      location = case __STACKTRACE__ do
        [{module, function, _arity, metadata} | _] ->
          " at=#{inspect(module)}.#{function}:#{Keyword.get(metadata, :line, 0)}"
        _ -> ""
      end

      Logger.error("FE reception failed tenant=#{tenant} exception=#{inspect(exception.__struct__)}#{database_error}#{location}")
      {:error, :reception_unavailable}
  end

  defp receiver(tenant, prefix) do
    with true <- Tenants.valid_identifier?(tenant),
         directory <- Path.join(Application.fetch_env!(:tigoo_server, :fe_receivers_directory), tenant),
         {:ok, files} <- File.ls(directory),
         [filename] <- Enum.filter(files, &(String.downcase(Path.extname(&1)) == ".p12")),
         path <- Path.join(directory, filename),
         true <- File.regular?(path),
         {:ok, credentials} <- File.read(Path.join(directory, "credentials.txt")),
         [[password]] <- Regex.scan(~r/^[\t ]*Password[\t ]*[:=][\t ]*([^\r\n]+)\r?$/mi,
           credentials, capture: :all_but_first),
         password <- password |> String.trim() |> String.trim("\"") |> String.trim("'"),
         true <- password != "",
         [rnc] <- Repo.all(from(c in Company, where: c.active == true,
           select: c.rnc, distinct: true, limit: 2), prefix: prefix),
         true <- is_binary(rnc) and Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, rnc) do
      {:ok, %{rnc: rnc, p12_path: path, password: password}}
    else
      _ -> {:error, :reception_unavailable}
    end
  end

  defp check_invoice(document, invoice, xml, token_identity, receiver, prefix) do
    with :ok <- FeXml.validate(document, invoice.type) |> log_failure(:invoice_schema),
         {:ok, signer} <- FeSignature.verify_ecf(xml) |> log_failure(:invoice_signature),
         true <- signer.certificate_sha256 == token_identity.certificate_sha256 do
      cond do
        invoice.buyer_rnc != receiver.rnc -> {:reject, 4}
        duplicate?(invoice, prefix) -> {:reject, 3}
        true -> :ok
      end
    else
      {:error, :invalid_schema} -> {:reject, 1}
      {:error, :invalid_signature} -> {:reject, 2}
      {:error, :verifier_unavailable} = error -> error
      false -> {:reject, 2}
    end
  end

  defp duplicate?(invoice, prefix) do
    Repo.exists?(from(e in FeReceivedEcf,
      where: e.issuer_rnc == ^invoice.issuer_rnc and e.encf == ^invoice.encf), prefix: prefix)
  end

  defp accept(invoice, xml, identity, receiver, prefix) do
    with {:ok, acknowledgement} <- receipt(invoice, receiver, nil) do
      attrs = Map.merge(invoice, %{xml: xml, receipt_xml: acknowledgement.xml,
        certificate_sha256: identity.certificate_sha256})

      case Repo.insert(FeReceivedEcf.changeset(attrs), prefix: prefix) do
        {:ok, _record} -> {:ok, acknowledgement}
        {:error, changeset} ->
          if Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
            Keyword.get(metadata, :constraint) == :unique
          end) do
            # The unique index also covers simultaneous submissions.
            receipt(invoice, receiver, 3)
          else
            Logger.error("FE reception failed stage=invoice_storage reason=invalid_changeset")
            {:error, :reception_unavailable}
          end
      end
    end
  end

  defp receipt(invoice, receiver, reason) do
    timestamp = DateTime.utc_now() |> DateTime.add(-4 * 3600, :second)
      |> Calendar.strftime("%d-%m-%Y %H:%M:%S")

    fields = [
      {"Version", "1.0"}, {"RNCEmisor", invoice.issuer_rnc},
      {"RNCComprador", receiver.rnc}, {"eNCF", invoice.encf},
      {"Estado", if(is_nil(reason), do: "0", else: "1")}
    ] ++ if(is_nil(reason), do: [], else: [{"CodigoMotivoNoRecibido", Integer.to_string(reason)}])
    fields = fields ++ [{"FechaHoraAcuseRecibo", timestamp}]

    xml = element("ARECF", [], [element("DetalleAcusedeRecibo", [],
      Enum.map(fields, fn {name, value} -> element(name, [], characters(value)) end))])
      |> Saxy.encode!(version: "1.0", encoding: "UTF-8")

    with {:ok, signed} <- Sign.sign(xml, receiver.p12_path, receiver.password) |> log_failure(:receipt_signing),
         :ok <- FeXml.validate_receipt(signed) |> log_failure(:receipt_schema) do
      {:ok, %{xml: signed, details: Map.new(fields)}}
    else
      _ -> {:error, :reception_unavailable}
    end
  end

  defp log_failure({:error, reason} = result, stage) when is_atom(reason) do
    Logger.error("FE reception failed stage=#{stage} reason=#{reason}")
    result
  end

  defp log_failure(result, _stage), do: result
end
