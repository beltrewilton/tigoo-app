defmodule TigooServer.Retaily.SequenceIssuer do
  @moduledoc false
  import Ecto.Query

  alias TigooServer.{Repo, TenantContext}
  alias TigooServer.Retaily.{Sequence, SequenceRotation}

  # Call inside the checkout transaction so issuing a number rolls back with the sale.
  def next(code, tenant, electronic? \\ false, force_next_current_seq \\ false) do
    rotation = Repo.one(from(s in SequenceRotation,
      where: s.code == ^code or s.prefix == ^code,
      order_by: [desc: s.code == ^code, asc: s.id], limit: 1), prefix: tenant)

    if rotation do
      previous = TenantContext.get_tenant()
      TenantContext.put_tenant(tenant)

      try do
        with {:ok, result} <- SequenceRotation.next(rotation.code, force_next_current_seq) do
          identifier = if result.actionable, do: result.current_seq, else: result.identifier
          {:ok, %{identifier: identifier, actionable: result.actionable,
            source: "rotation", code: result.code}}
        end
      after
        if is_nil(previous), do: TenantContext.clear_tenant(), else: TenantContext.put_tenant(previous)
      end
    else
      next_standard(code, tenant, electronic?)
    end
  end

  def force_next?(attrs) do
    Map.get(attrs, "force_next_current_seq", Map.get(attrs, :force_next_current_seq, false)) in [true, "true", "on", "1", 1]
  end

  defp next_standard(code, tenant, electronic?) do
    case Repo.one(from(s in Sequence, where: s.code == ^code, lock: "FOR UPDATE"), prefix: tenant) do
      nil -> {:error, :sequence_not_found}
      sequence ->
        if electronic? and (sequence.increment_by != 1 or sequence.fill != 10 or
             not is_integer(sequence.current_seq) or sequence.current_seq < 0 or
             sequence.current_seq >= 9_999_999_999 or sequence.prefix != code) do
          {:error, :invalid_ecf_test_sequence}
        else
          next = sequence.current_seq + sequence.increment_by
          with {:ok, _} <- sequence |> Ecto.Changeset.change(current_seq: next) |> Repo.update(prefix: tenant) do
            identifier = if electronic?,
              do: sequence.prefix <> String.pad_leading(Integer.to_string(next), sequence.fill, "0"),
              else: String.pad_trailing(sequence.prefix, sequence.fill, "0") <> Integer.to_string(next)
            {:ok, %{identifier: identifier, actionable: true, source: "standard", code: code}}
          end
        end
    end
  end
end
