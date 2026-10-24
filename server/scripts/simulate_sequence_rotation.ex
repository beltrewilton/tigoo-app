# Run from server/ with the application database configured:
#   mix run scripts/simulate_sequence_rotation.ex
# Optional report path:
#   mix run scripts/simulate_sequence_rotation.ex /tmp/ans_rotation_report.txt
# This script commits dedicated simulation rows in ans.app_sequence_rotation.
# It creates the ans schema and rotation table if missing, using the existing
# rotation migration. It does not modify existing sequences or the OS clock.
defmodule TigooServer.Scripts.SimulateSequenceRotation do
  import Ecto.Query

  alias TigooServer.{Repo, TenantContext}
  alias TigooServer.Retaily.{BusinessTime, SequenceRotation}

  @tenant "ans"
  @human_users ["PRISCILA"]
  @concurrent_calls_per_user 5

  def run do
    run_id = Integer.to_string(System.system_time(:microsecond))
    path = List.first(System.argv()) || Path.join("tmp", "ans_rotation_#{run_id}.txt")
    File.mkdir_p!(Path.dirname(Path.expand(path)))
    {:ok, output} = File.open(path, [:write, :exclusive, :utf8])
    previous_tenant = TenantContext.get_tenant()
    TenantContext.put_tenant(@tenant)

    try do
      log(output, "ROTATING SEQUENCE DATABASE SIMULATION")
      log(output, "Tenant: #{@tenant} | Run: #{run_id} | Month: #{month()}")
      log(output, "Rows use unique SIM codes and remain committed for inspection.")
      log(output, "A simulation clock advances through three consecutive months; database periods are not rewound.")
      log(output, "The OS clock is unchanged. Results are listed in lock acquisition order.")

      initialize_table!(output)
      calls_text = Enum.at(System.argv(), 1, "500")
      calls = case Integer.parse(calls_text) do
        {value, ""} when value > 0 -> value
        _ -> raise "Calls per user must be a positive integer"
      end
      row = insert!(run_id, "USERS")
      log(output, "Three monthly windows | #{calls} calls per user per period")
      log(output, "Estimated monthly amount: #{row.consumer_estatimation_monthly_amount}")
      log(output, "Allowed monthly amount: #{row.consumer_allowed_monthly_amount} | Average: #{row.consumer_avg}")
      log(output, "Window: #{row.rotation_available} values | Steps: #{row.rotation_allowed_steps} | Initial base: #{row.current_seq}")

      first_month = month()
      final = Enum.reduce(1..3, row, fn index, row ->
        period = if index == 1, do: first_month,
          else: row.period |> Date.end_of_month() |> Date.add(1)
        IO.puts("Period #{index}/3 (#{period}): #{calls} calls per user...")
        human_users!(output, row, "PERIOD #{index} OF 3 — #{period}", calls, period)
      end)
      log(output, "\nALL 3 PERIODS PASSED | #{3 * length(@human_users) * calls} total calls")
      log(output, "Database row retained: id=#{final.id}, code=#{final.code}")
      IO.puts("Simulation complete. Report: #{Path.expand(path)}")
    rescue
      error ->
        log(output, "\nFAIL: #{Exception.message(error)}")
        log(output, "Earlier calls remain committed; inspect the report and SIM rows.")
        reraise error, __STACKTRACE__
    after
      try do
        if is_nil(previous_tenant) do
          TenantContext.clear_tenant()
        else
          TenantContext.put_tenant(previous_tenant)
        end
      after
        File.close(output)
      end
    end
  end

  defp initialize_table!(output) do
    Repo.query!("CREATE SCHEMA IF NOT EXISTS ans")

    %{rows: [[exists?]]} = Repo.query!(
      "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = $2)",
      [@tenant, "app_sequence_rotation"]
    )

    if exists? do
      log(output, "SETUP | ans.app_sequence_rotation already exists; existing rows preserved")
    else
      migration = Path.expand("../priv/repo/tenant_migrations/20261017000000_create_app_sequence_rotation.exs", __DIR__)
      Code.require_file(migration)

      case Ecto.Migrator.up(Repo, 20261017000000,
             TigooServer.Repo.Migrations.CreateAppSequenceRotation,
             prefix: @tenant, log: false) do
        :ok -> log(output, "SETUP | created ans.app_sequence_rotation using the rotation migration")
        :already_up -> raise "Rotation migration is marked applied but ans.app_sequence_rotation is missing"
      end
    end

    # Fail before seeding if an older table is missing required state columns.
    Repo.query!("SELECT rotation_window_start, current_seq_rotation, rotation_available, rotation_allowed_steps FROM ans.app_sequence_rotation LIMIT 0")
  end

  defp insert!(run_id, suffix, overrides \\ %{}) do
    attrs = Map.merge(%{
      code: "SIM#{run_id}#{suffix}", name: "Rotation simulation #{run_id} #{suffix}",
      prefix: "B02", fill: 8, increment_by: 99, current_seq: 35700,
      consumer_avg: Decimal.new(3_700), consumer_allowed_monthly_amount: Decimal.new(250_000),
      consumer_estatimation_monthly_amount: Decimal.new(2_300_000)
    }, overrides)

    %SequenceRotation{}
    |> SequenceRotation.changeset(attrs)
    |> Repo.insert!(prefix: @tenant)
  end

  defp human_users!(output, row, title, calls_per_user, period) do
    count = length(@human_users) * calls_per_user
    started = System.monotonic_time(:millisecond)
    log(output, "\n#{title}\nCode: #{row.code}")
    log(output, "#{Enum.join(@human_users, ", ")}; #{calls_per_user} calls each; #{@concurrent_calls_per_user} concurrent calls per user; no pauses")
    log(output, "Window starts at #{row.current_seq + 1} | Base before period: #{row.current_seq}")
    forced_calls = Map.new(@human_users, fn user -> {user, :rand.uniform(calls_per_user)} end)
    Enum.each(@human_users, fn user ->
      log(output, "Random forced request: #{user} ##{Map.fetch!(forced_calls, user)}")
    end)
    log(output, " USER      CALL    IDENTIFIER   PERIOD      CURRENT_SEQ  ACTIONABLE  FORCED")
    log(output, " --------  ------  -----------  ----------  -----------  ----------  ------")

    order_counter = :atomics.new(1, [])

    results =
      for(user <- @human_users, worker <- 1..@concurrent_calls_per_user, do: {user, worker})
      |> Task.async_stream(fn {user, worker} ->
        # Each user has five workers; every call number belongs to one worker.
        TenantContext.put_tenant(@tenant)

        1..calls_per_user
        |> Enum.filter(fn call -> rem(call - 1, @concurrent_calls_per_user) == worker - 1 end)
        |> Enum.map(fn call ->
          force = call == Map.fetch!(forced_calls, user)
          result = next_with_state(row, period, force, order_counter)
          {user, call, force, result}
        end)
      end, max_concurrency: length(@human_users) * @concurrent_calls_per_user,
        ordered: false, timeout: :infinity)
      |> Enum.flat_map(fn
        {:ok, calls} -> calls
        other -> raise "Human user task failed: #{inspect(other)}"
      end)

    results = Enum.sort_by(results, fn
      {_user, _call, _force, {:ok, {order, _value, _state, _actionable}}} -> order
      failure -> raise "Human request failed: #{inspect(failure)}"
    end)
    assert!(length(results) == count, "Unexpected number of calls")
    expected_final = Enum.reduce(results, row, fn
      {user, call, force, {:ok, {_order, value, state, actionable}}}, before ->
        expected = expected_state(before, period, force)
        assert!(snapshot(state) == snapshot(expected), "Incorrect state for #{user} call #{call}")
        expected_actionable = is_nil(before.period) or expected.current_seq != before.current_seq
        assert!(value == identifier(expected, expected.current_seq_rotation), "Incorrect identifier")
        assert!(actionable == expected_actionable, "Incorrect actionable flag")
        log(output, " #{String.pad_trailing(user, 8)}  #{String.pad_leading(to_string(call), 6)}  " <>
          "#{String.pad_trailing(value, 11)}  #{state.period}  #{String.pad_leading(to_string(state.current_seq), 11)}  " <>
          "#{String.pad_trailing(to_string(actionable), 10)}  #{force}")
        expected
    end)
    final = get!(row.id)
    actual_state = final |> snapshot() |> Map.delete(:update_on)
    expected_state = expected_final |> snapshot() |> Map.delete(:update_on)
    assert!(actual_state == expected_state, "Human-user final state differs")
    log(output, "\nPASS | #{count} successful human requests | elapsed #{System.monotonic_time(:millisecond) - started} ms")
    log(output, "FINAL | base=#{final.current_seq} | step=#{final.rotation_step} | cursor=#{final.current_seq_rotation} | window=#{final.rotation_window_start}..#{upper(final)} | period=#{final.period}")
    final
  end

  # Keep the row locked until its post-call state has been captured. A separate
  # read after next/1 commits could observe another user's base instead.
  defp next_with_state(row, period, force, order_counter) do
    Repo.transaction(fn ->
      Repo.one!(
        from(sequence in SequenceRotation, where: sequence.id == ^row.id, lock: "FOR UPDATE"),
        prefix: @tenant
      )

      order = :atomics.add_get(order_counter, 1, 1)

      clock = fn tenant ->
        time = BusinessTime.local_now(tenant) |> NaiveDateTime.to_time()
        NaiveDateTime.new!(period, time)
      end

      case SequenceRotation.next(row.code, force, clock) do
        {:ok, %{identifier: identifier, actionable: actionable}} ->
          state = get!(row.id)
          {order, identifier, state, actionable}

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp expected_state(before, period, force) do
    allowed = Decimal.to_integer(before.rotation_allowed_steps)
    available = Decimal.to_integer(before.rotation_available)
    new_period = is_nil(before.period) or before.period != period

    {base, step, start, cursor} = if new_period do
      start = before.current_seq + 1
      base = if is_nil(before.period), do: before.current_seq, else: start
      {base, 1, start, start}
    else
      step = rem(Decimal.to_integer(before.rotation_step), allowed) + 1
      advance = force or step == 1
      base = before.current_seq + if(advance, do: 1, else: 0)
      start = before.rotation_window_start
      cursor = if force, do: base,
        else: start + rem(before.current_seq_rotation - start + 1, available)
      {base, step, start, cursor}
    end

    %{before | period: period, current_seq: base, rotation_step: Decimal.new(step),
      rotation_window_start: start, current_seq_rotation: cursor}
  end

  defp snapshot(row), do: Map.take(row, [:period, :current_seq, :rotation_step,
    :rotation_window_start, :current_seq_rotation])
  defp get!(id), do: Repo.one!(from(row in SequenceRotation, where: row.id == ^id), prefix: @tenant)
  defp upper(row), do: row.rotation_window_start + Decimal.to_integer(row.rotation_available) - 1
  defp month, do: BusinessTime.local_now(@tenant) |> NaiveDateTime.to_date() |> Date.beginning_of_month()
  defp identifier(row, cursor), do: row.prefix <> String.pad_leading(to_string(cursor), row.fill, "0")
  defp assert!(true, _message), do: :ok
  defp assert!(false, message), do: raise(message)
  defp log(output, line), do: IO.write(output, line <> "\n")
end

TigooServer.Scripts.SimulateSequenceRotation.run()
