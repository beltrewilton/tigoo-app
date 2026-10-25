modules = [TigooServer.Fe.Client, TigooServer.Fe.Client.CLI, TigooServer.Fe.Client.Error,
  TigooServer.Fe.Submission, TigooServer.Fe.Credentials, TigooServer.Sign,
  TigooServer.Fe.Generation.Schema, TigooServer.Fe.Generation.Command,
  TigooServer.Fe.Generation.Error, TigooServer.Fe.Generation.Rules,
  TigooServer.Fe.Generation.Xml, Req, Saxy, Decimal, Jason]

unless Enum.all?(modules, &Code.ensure_loaded?/1) do
  IO.puts(:stderr, "DGII client modules/dependencies are not built for MIX_ENV=#{Mix.env()}. Build them through the normal project workflow first. This script never compiles project modules.")
  System.halt(2)
end

System.halt(TigooServer.Fe.Client.CLI.main(System.argv()))
