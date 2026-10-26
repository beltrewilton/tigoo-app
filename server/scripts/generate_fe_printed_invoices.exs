modules = [TigooServer.Fe.PrintedInvoice, TigooServer.Fe.PrintedInvoice.CLI,
  TigooServer.Fe.PrintedInvoice.Template, TigooServer.Fe.PrintedInvoice.Qr,
  QQR, QQR.SVG, TigooServer.Fe.Generation.Artifact,
  TigooServer.Fe.Generation.Command, TigooServer.Fe.Generation.Schema,
  TigooServer.Fe.Generation.Xml, TigooServer.Fe.Generation.Error,
  TigooServer.Sign, Saxy, Decimal, Jason]

unless Enum.all?(modules, &Code.ensure_loaded?/1) do
  IO.puts(:stderr, "Printed invoice modules/dependencies are not built. Rebuild through the normal project workflow first. This script never compiles.")
  System.halt(2)
end

stale = Enum.filter(modules, fn module ->
  source = module.module_info(:compile)[:source]
  beam = :code.which(module)
  if is_list(source) and is_list(beam) do
    case {File.stat(List.to_string(source), time: :posix), File.stat(List.to_string(beam), time: :posix)} do
      {{:ok, a}, {:ok, b}} -> a.mtime > b.mtime
      _ -> false
    end
  else
    false
  end
end)
if stale != [] do
  IO.puts(:stderr, "Compiled modules are older than source: #{Enum.map_join(stale, ", ", &inspect/1)}. Rebuild normally before generating PDFs. No files were generated.")
  System.halt(2)
end

Enum.each([:crypto, :public_key], fn app ->
  case Application.ensure_all_started(app) do
    {:ok, _} -> :ok
    {:error, _} -> IO.puts(:stderr, "Cannot start #{app}"); System.halt(2)
  end
end)
System.halt(TigooServer.Fe.PrintedInvoice.CLI.main(System.argv()))
