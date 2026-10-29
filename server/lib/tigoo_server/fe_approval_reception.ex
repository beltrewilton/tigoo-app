defmodule TigooServer.FeApprovalReception do
  @moduledoc "Receives signed ACECF documents without changing operational sales."
  import Ecto.Query
  require Logger

  alias TigooServer.{FeReceivedApproval, FeSignature, FeXml, Repo}
  alias TigooServer.Accounts.Company

  def receive_approval(tenant, xml, identity) do
    prefix = Triplex.to_prefix(tenant)

    with {:ok, issuer_rnc} <- company_rnc(prefix),
         {:ok, approval} <- FeXml.parse_approval(xml),
         :ok <- intended_issuer(approval, issuer_rnc),
         {:ok, signer} <- FeSignature.verify_approval(xml),
         :ok <- same_signer(signer, identity),
         {:ok, _record} <- store(prefix, approval, xml, signer) do
      Logger.info("FE commercial approval result=received tenant=#{tenant} state=#{approval.state}")
      :ok
    else
      {:error, %Ecto.Changeset{}} ->
        Logger.error("FE commercial approval stage=storage result=invalid_changeset tenant=#{tenant}")
        {:error, :reception_unavailable}
      {:error, reason} = error ->
        Logger.warning("FE commercial approval result=rejected tenant=#{tenant} reason=#{reason}")
        error
    end
  rescue
    exception ->
      Logger.error("FE commercial approval result=unavailable tenant=#{tenant} exception=#{inspect(exception.__struct__)}")
      {:error, :reception_unavailable}
  end

  defp company_rnc(prefix) do
    case Repo.all(from(c in Company, where: c.active == true,
      select: c.rnc, distinct: true, limit: 2), prefix: prefix) do
      [rnc] when is_binary(rnc) ->
        if Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, rnc),
          do: {:ok, rnc}, else: {:error, :reception_unavailable}
      _ -> {:error, :reception_unavailable}
    end
  end

  # The approval is sent by the buyer to the invoice's issuer. A personal
  # certificate's subject ID is not the company's RNC.
  defp intended_issuer(%{issuer_rnc: actual}, expected) when actual == expected, do: :ok
  defp intended_issuer(_, _), do: {:error, :wrong_issuer}

  defp same_signer(%{certificate_sha256: actual}, %{certificate_sha256: expected}) when actual == expected, do: :ok
  defp same_signer(_, _), do: {:error, :invalid_signature}

  defp store(prefix, approval, xml, signer) do
    attrs = approval
      |> Map.put(:amount, approval.amount_dop)
      |> Map.put(:xml, xml)
      |> Map.put(:xml_sha256, :crypto.hash(:sha256, xml) |> Base.encode16(case: :lower))
      |> Map.put(:certificate_sha256, signer.certificate_sha256)

    # Do not require a sales row: certification references may not be present
    # in operational sales. Preserve each distinct signed document as evidence.
    Repo.insert(FeReceivedApproval.changeset(attrs), prefix: prefix,
      on_conflict: :nothing, conflict_target: [:issuer_rnc, :buyer_rnc, :encf, :xml_sha256])
  end
end
