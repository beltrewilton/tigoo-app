defmodule TigooServer.Fe.Generation.Command do
  @moduledoc false
  alias TigooServer.Fe.Generation.Error

  def run!(executable, arguments, timeout \\ 30_000) do
    path = System.find_executable(executable) || Error.fail!(:dependency, "Executable unavailable: #{executable}")
    port = Port.open({:spawn_executable, path}, [
      :binary, :exit_status, :stderr_to_stdout, :use_stdio, args: arguments
    ])

    receive_output(port, System.monotonic_time(:millisecond) + timeout, "")
  end

  defp receive_output(port, deadline, output) do
    if System.monotonic_time(:millisecond) >= deadline do
      Port.close(port)
      Error.fail!(:validation, "Native command timed out")
    end
    receive do
      {^port, {:data, bytes}} ->
        # Keep diagnostics bounded even if a native tool emits very large errors.
        remaining = max(65_536 - byte_size(output), 0)
        receive_output(port, deadline, output <> binary_part(bytes, 0, min(byte_size(bytes), remaining)))
      {^port, {:exit_status, 0}} -> output
      {^port, {:exit_status, status}} ->
        Error.fail!(:validation, "Native command exited #{status}: #{String.slice(output, 0, 4000)}")
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Port.close(port)
        Error.fail!(:validation, "Native command timed out")
    end
  end
end
