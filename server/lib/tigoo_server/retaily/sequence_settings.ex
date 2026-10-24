defmodule TigooServer.Retaily.SequenceSettings do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias TigooServer.{Repo, TenantContext}
  alias TigooServer.Retaily.{Sequence, SequenceRotation}

  @max_sequence 9_223_372_036_854_775_807
  @rotation_fields ~w(name code prefix fill current_seq consumer_estatimation_monthly_amount consumer_allowed_monthly_amount consumer_avg)
  @standard_fields ~w(name code prefix fill increment_by current_seq)

  def list do
    tenant = TenantContext.tenant!()
    %{
      standard: Repo.all(from(s in Sequence, order_by: s.code), prefix: tenant),
      rotation: Repo.all(from(s in SequenceRotation, order_by: s.code), prefix: tenant)
    }
  end

  def new("standard"), do: %Sequence{fill: 8, increment_by: 1, current_seq: 0}
  def new("rotation"), do: %SequenceRotation{fill: 8, current_seq: 0}

  def change("standard", record, attrs) do
    Sequence.changeset(record, Map.take(attrs, @standard_fields))
  end

  def change("rotation", record, attrs) do
    attrs = Map.take(attrs, @rotation_fields)
    # The generator owns the base after initialization, even if a stale form
    # or a crafted request attempts to send it back.
    attrs = if record.rotation_window_start, do: Map.delete(attrs, "current_seq"), else: attrs

    record
    |> SequenceRotation.changeset(attrs)
    |> validate_required([:name, :code, :prefix, :fill, :current_seq,
      :consumer_estatimation_monthly_amount, :consumer_allowed_monthly_amount, :consumer_avg])
    |> validate_format(:prefix, ~r/\A[A-Za-z0-9]+\z/)
    |> validate_number(:fill, greater_than: 0)
    |> validate_number(:current_seq, greater_than_or_equal_to: 0, less_than: @max_sequence)
    |> validate_number(:consumer_estatimation_monthly_amount, greater_than: 0)
    |> validate_number(:consumer_allowed_monthly_amount, greater_than: 0)
    |> validate_number(:consumer_avg, greater_than: 0)
    |> validate_rotation_counts()
  end

  def save(kind, id, attrs) when kind in ["standard", "rotation"] do
    tenant = TenantContext.tenant!()
    schema = if kind == "standard", do: Sequence, else: SequenceRotation

    Repo.transaction(fn ->
      record = if id do
        Repo.one(from(s in schema, where: s.id == ^id, lock: "FOR UPDATE"), prefix: tenant) ||
          Repo.rollback(:not_found)
      else
        new(kind)
      end

      case Repo.insert_or_update(change(kind, record, attrs), prefix: tenant) do
        {:ok, record} -> record
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def delete_standard(id) do
    case Repo.get(Sequence, id, prefix: TenantContext.tenant!()) do
      nil -> {:error, :not_found}
      record -> Repo.delete(record, prefix: TenantContext.tenant!())
    end
  end

  defp validate_rotation_counts(%{valid?: false} = changeset), do: changeset
  defp validate_rotation_counts(changeset) do
    estimate = get_field(changeset, :consumer_estatimation_monthly_amount)
    amount = get_field(changeset, :consumer_allowed_monthly_amount)
    average = get_field(changeset, :consumer_avg)
    available = Decimal.round(Decimal.div(amount, average), 0)

    if Decimal.compare(available, Decimal.new(1)) == :lt do
      add_error(changeset, :consumer_allowed_monthly_amount, "must provide at least one rotation value")
    else
      steps = Decimal.round(Decimal.div(Decimal.round(Decimal.div(estimate, average), 0), available), 0)
      cond do
        Decimal.compare(available, Decimal.new(@max_sequence)) == :gt ->
          add_error(changeset, :consumer_allowed_monthly_amount, "rotation window is too large")
        Decimal.compare(steps, Decimal.new(1)) == :lt ->
          add_error(changeset, :consumer_estatimation_monthly_amount, "must provide at least one allowed step")
        Decimal.compare(steps, Decimal.new(@max_sequence)) == :gt ->
          add_error(changeset, :consumer_estatimation_monthly_amount, "allowed step count is too large")
        get_field(changeset, :current_seq) + Decimal.to_integer(available) > @max_sequence ->
          add_error(changeset, :current_seq, "does not leave enough space for the rotation window")
        true -> changeset
      end
    end
  end
end
