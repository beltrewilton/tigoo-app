defmodule PosServer.Retaily.SequenceRotation do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias PosServer.{Repo, TenantContext}
  alias PosServer.Retaily.BusinessTime

  @max_sequence 9_223_372_036_854_775_807

  schema "app_sequence_rotation" do
    field :period, :date
    field :consumer_estatimation_monthly_amount, :decimal
    field :consumer_allowed_monthly_amount, :decimal
    field :consumer_avg, :decimal
    field :rotation_available, :decimal, read_after_writes: true
    field :rotation_allowed_steps, :decimal, read_after_writes: true
    field :rotation_step, :decimal
    field :name, :string
    field :code, :string
    field :prefix, :string
    field :fill, :integer
    field :increment_by, :integer
    field :current_seq, :integer
    field :rotation_window_start, :integer
    field :current_seq_rotation, :integer
    field :update_on, :naive_datetime
  end

  @doc """
  Issues a rotating identifier in the current tenant's schema.

  Uses the tenant business clock and calendar months. `fill` is a minimum
  width; digits are never truncated. `increment_by` is intentionally ignored.
  `current_seq` is the step-group base, while `current_seq_rotation` is the
  last emitted number. Configuration must remain fixed during an active month.

  A new record requires a nonnegative `current_seq`; its cursor and window
  start must be nil. Its first emission uses step 1.

  Returns `{:ok, details}` or `{:error, reason}`. Details include `identifier`,
  `actionable`, tenant and sequence identity, formatting configuration,
  persisted period/base/cursor/step, integer rotation counts, inclusive window
  boundaries, and `update_on`. All state describes this call's committed update.
  The returned `current_seq` uses the same prefix and padding as `identifier`;
  its database value remains numeric.
  `actionable` is true on initialization, a new month,
  or a base advance (scheduled or forced). Wrapping alone does not set it.
  Database failures are returned without issuing a value.

  With `force_next_current_seq` set to true (the second positional argument), an
  existing month's base advances by one and that base is emitted immediately.
  The normal step schedule and fixed window are preserved. A coincident step
  reset advances the base once. Initialization and month transitions take
  precedence. A forced value outside the window is rejected atomically.
  """
  def next(code, force_next_current_seq \\ false)

  def next(code, force_next_current_seq) when is_boolean(force_next_current_seq),
    do: next(code, force_next_current_seq, &BusinessTime.local_now/1)

  # Preserve the existing simulation clock call form.
  def next(code, clock) when is_function(clock, 1), do: next(code, false, clock)
  def next(_code, _argument), do: {:error, :invalid_arguments}

  @doc "Same as next/2, with an explicit tenant clock for controlled simulations."
  def next(code, force_next_current_seq, clock)
      when is_binary(code) and byte_size(code) > 0 and
             is_boolean(force_next_current_seq) and is_function(clock, 1) do
    case TenantContext.get_tenant() do
      tenant when is_binary(tenant) and byte_size(tenant) > 0 ->
        Repo.transaction(fn ->
          sequence =
            Repo.one(
              from(sequence in __MODULE__,
                where: sequence.code == ^code,
                lock: "FOR UPDATE"
              ),
              prefix: tenant
            ) || Repo.rollback(:not_found)

          # Read after the lock: a waiting request may cross a month boundary.
          now = clock.(tenant)
          period = now |> NaiveDateTime.to_date() |> Date.beginning_of_month()
          available = positive_counter!(sequence.rotation_available, :rotation_available)
          allowed_steps = positive_counter!(sequence.rotation_allowed_steps, :rotation_allowed_steps)
          validate_configuration!(sequence)
          attrs = next_state!(sequence, period, available, allowed_steps)
          attrs = maybe_force_base!(sequence, attrs, period, available, force_next_current_seq)
          value = attrs.current_seq_rotation

          case Repo.update(change(sequence, Map.put(attrs, :update_on, now)), prefix: tenant) do
            {:ok, updated_sequence} ->
              identifier =
                sequence.prefix <> String.pad_leading(Integer.to_string(value), sequence.fill, "0")

              %{
                identifier: identifier,
                actionable: is_nil(sequence.period) or attrs.current_seq != sequence.current_seq,
                tenant: tenant,
                id: updated_sequence.id,
                code: updated_sequence.code,
                name: updated_sequence.name,
                prefix: updated_sequence.prefix,
                fill: updated_sequence.fill,
                period: updated_sequence.period,
                current_seq:
                  updated_sequence.prefix <>
                    String.pad_leading(Integer.to_string(updated_sequence.current_seq), updated_sequence.fill, "0"),
                current_seq_rotation: updated_sequence.current_seq_rotation,
                rotation_step: Decimal.to_integer(updated_sequence.rotation_step),
                rotation_available: available,
                rotation_allowed_steps: allowed_steps,
                rotation_window_start: updated_sequence.rotation_window_start,
                rotation_window_end: updated_sequence.rotation_window_start + available - 1,
                update_on: updated_sequence.update_on
              }

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      _ ->
        {:error, :tenant_not_set}
    end
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError, Ecto.ConstraintError] ->
      {:error, {:database_error, error}}
  end

  def next(code, _force_next_current_seq, _clock) when not is_binary(code) or code == "",
    do: {:error, :invalid_code}

  def next(_code, _force_next_current_seq, _clock), do: {:error, :invalid_arguments}

  defp maybe_force_base!(sequence, attrs, period, available, true) do
    if match?(%Date{}, sequence.period) and Date.beginning_of_month(sequence.period) == period do
      base = checked_sequence!(sequence.current_seq + 1)
      upper = checked_sequence!(attrs.rotation_window_start + available - 1)

      if base < attrs.rotation_window_start or base > upper do
        invalid!(:forced_value_outside_window)
      end

      %{attrs | current_seq: base, current_seq_rotation: base}
    else
      attrs
    end
  end

  defp maybe_force_base!(_sequence, attrs, _period, _available, false), do: attrs

  defp next_state!(sequence, period, available, allowed_steps) do
    case sequence.period do
      nil ->
        if not is_nil(sequence.rotation_window_start) or not is_nil(sequence.current_seq_rotation) do
          invalid!(:uninitialized_state)
        end

        initialize_window!(sequence.current_seq, sequence.current_seq + 1, period, available)

      %Date{} = stored_period ->
        stored_month = Date.beginning_of_month(stored_period)

        case Date.compare(stored_month, period) do
          :gt -> invalid!(:future_period)
          :lt ->
            base = checked_sequence!(sequence.current_seq + 1)
            initialize_window!(base, base, period, available)
          :eq -> advance_window!(sequence, period, available, allowed_steps)
        end
    end
  end

  defp initialize_window!(base, start, period, available) do
    start = checked_sequence!(start)
    checked_sequence!(start + available - 1)

    %{
      period: period,
      current_seq: base,
      rotation_window_start: start,
      current_seq_rotation: start,
      rotation_step: Decimal.new(1)
    }
  end

  defp advance_window!(sequence, period, available, allowed_steps) do
    start = sequence.rotation_window_start
    cursor = sequence.current_seq_rotation
    step = positive_counter!(sequence.rotation_step, :rotation_step)

    if not is_integer(start) or start < 1 or not is_integer(cursor) or step > allowed_steps do
      invalid!(:rotation_state)
    end

    upper = checked_sequence!(start + available - 1)
    if cursor < start or cursor > upper, do: invalid!(:rotation_cursor)

    {base, next_step} =
      if step == allowed_steps do
        {checked_sequence!(sequence.current_seq + 1), 1}
      else
        {sequence.current_seq, step + 1}
      end

    %{
      period: period,
      current_seq: base,
      rotation_window_start: start,
      current_seq_rotation: if(cursor == upper, do: start, else: cursor + 1),
      rotation_step: Decimal.new(next_step)
    }
  end

  defp validate_configuration!(sequence) do
    if not is_integer(sequence.current_seq) or sequence.current_seq < 0 or
         sequence.current_seq > @max_sequence do
      invalid!(:current_seq)
    end

    if not is_integer(sequence.fill) or sequence.fill < 1, do: invalid!(:fill)

    if not is_binary(sequence.prefix) or not Regex.match?(~r/\A[A-Za-z0-9]+\z/, sequence.prefix) do
      invalid!(:prefix)
    end
  end

  defp positive_counter!(%Decimal{} = value, field) do
    if Decimal.nan?(value) or Decimal.inf?(value), do: invalid!(field)
    if not Decimal.equal?(value, Decimal.round(value, 0)), do: invalid!(field)
    counter = Decimal.to_integer(value)
    if counter < 1 or counter > @max_sequence, do: invalid!(field)
    counter
  end

  defp positive_counter!(_value, field), do: invalid!(field)

  defp checked_sequence!(value) when value >= 0 and value <= @max_sequence, do: value
  defp checked_sequence!(_value), do: Repo.rollback(:sequence_overflow)

  defp invalid!(field), do: Repo.rollback({:invalid_configuration, field})

  def changeset(sequence_rotation, attrs) do
    sequence_rotation
    |> cast(attrs, [
      :period,
      :consumer_estatimation_monthly_amount,
      :consumer_allowed_monthly_amount,
      :consumer_avg,
      :rotation_step,
      :name,
      :code,
      :prefix,
      :fill,
      :increment_by,
      :current_seq,
      :rotation_window_start,
      :current_seq_rotation,
      :update_on
    ])
    |> unique_constraint(:code)
    |> protect_active_configuration()
  end

  # Configuration writers must use this changeset. Direct SQL updates bypass
  # this guard and must not alter configuration during an active month.
  defp protect_active_configuration(changeset) do
    fields = [
      :consumer_estatimation_monthly_amount,
      :consumer_allowed_monthly_amount,
      :consumer_avg,
      :prefix,
      :fill
    ]

    changed_fields = Enum.filter(fields, &Map.has_key?(changeset.changes, &1))
    sequence = changeset.data

    if changed_fields != [] and not is_nil(sequence.rotation_window_start) and
         match?(%Date{}, sequence.period) do
      tenant = sequence.__meta__.prefix || TenantContext.get_tenant()
      today = tenant |> BusinessTime.local_now() |> NaiveDateTime.to_date()

      if Date.beginning_of_month(sequence.period) == Date.beginning_of_month(today) do
        Enum.reduce(changed_fields, changeset, fn field, changeset ->
          add_error(changeset, field, "cannot change during an active month")
        end)
      else
        changeset
      end
    else
      changeset
    end
  end
end
