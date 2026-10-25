modules = [TigooServer.Fe.Generation, TigooServer.Fe.Generation.CLI,
  TigooServer.Fe.Generation.Workbook, TigooServer.Fe.Generation.Schema,
  TigooServer.Fe.Generation.Document, TigooServer.Fe.Generation.Rules,
  TigooServer.Fe.Generation.Error, TigooServer.Fe.Generation.Xml,
  TigooServer.Fe.Generation.Command, TigooServer.Fe.Generation.Artifact,
  TigooServer.Fe.Credentials, TigooServer.Sign, Saxy, Decimal, Jason]

unless Enum.all?(modules, &Code.ensure_loaded?/1) do
  IO.puts(:stderr, "Generation modules are not built for MIX_ENV=#{Mix.env()}. Build them through the normal project workflow before running this command. This script never compiles project modules.")
  System.halt(2)
end

System.halt(TigooServer.Fe.Generation.CLI.main(System.argv()))
