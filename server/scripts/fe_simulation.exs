modules = [TigooServer.Fe.Simulation, TigooServer.Fe.Simulation.CLI,
  TigooServer.Fe.Simulation.Cases, TigooServer.Fe.Simulation.SalesCsv,
  TigooServer.Fe.Simulation.Sequences, TigooServer.Fe.Generation,
  TigooServer.Fe.Generation.Schema, TigooServer.Fe.Generation.Document,
  TigooServer.Fe.Generation.Rules, TigooServer.Fe.Generation.Artifact,
  TigooServer.Fe.Generation.Xml, TigooServer.Fe.Generation.Command,
  TigooServer.Fe.Generation.Error, TigooServer.Fe.Credentials,
  TigooServer.Fe.Client, TigooServer.Fe.Client.Error, TigooServer.Fe.Submission,
  TigooServer.Sign, Saxy, Decimal, Jason, Req]

unless Enum.all?(modules, &Code.ensure_loaded?/1) do
  IO.puts(:stderr, "Simulation modules/dependencies must be built through the normal project workflow first. This script does not compile.")
  System.halt(2)
end

# --no-compile deliberately loads BEAM files; module availability alone does not
# establish that those files contain the current source changes.
stale = Enum.filter(modules, fn module ->
  source = module.module_info(:compile)[:source]
  beam = :code.which(module)
  if is_list(source) and is_list(beam) do
    case {File.stat(List.to_string(source), time: :posix), File.stat(List.to_string(beam), time: :posix)} do
      {{:ok, source_stat}, {:ok, beam_stat}} -> source_stat.mtime > beam_stat.mtime
      _ -> false
    end
  else
    false
  end
end)
if stale != [] do
  IO.puts(:stderr, "Compiled modules are older than their source: #{Enum.map_join(stale, ", ", &inspect/1)}. Rebuild through the normal project workflow, then rerun. Nothing was generated or submitted.")
  System.halt(2)
end
System.halt(TigooServer.Fe.Simulation.CLI.main(System.argv()))
