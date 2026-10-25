modules = [TigooServer.Fe.CommercialApproval, TigooServer.Fe.CommercialApproval.Document,
  TigooServer.Fe.CommercialApproval.CLI, TigooServer.Fe.Client, TigooServer.Fe.Client.Error,
  TigooServer.Fe.Submission, TigooServer.Fe.Credentials, TigooServer.Sign,
  TigooServer.Fe.Generation.Artifact, TigooServer.Fe.Generation.Workbook,
  TigooServer.Fe.Generation.Schema, TigooServer.Fe.Generation.Command,
  TigooServer.Fe.Generation.Error, TigooServer.Fe.Generation.Rules,
  TigooServer.Fe.Generation.Xml, Req, Saxy, Decimal, Jason]

unless Enum.all?(modules, &Code.ensure_loaded?/1) do
  IO.puts(:stderr, "ACECF modules/dependencies are not built for MIX_ENV=#{Mix.env()}. Build through the normal project workflow first. This command never compiles project modules.")
  System.halt(2)
end

case System.argv() do
  [mode | arguments] when mode in ["generate", "submit"] ->
    System.halt(TigooServer.Fe.CommercialApproval.CLI.main(mode, arguments))
  _ ->
    IO.puts(:stderr, "Use generate_fe_approvals.sh or submit_fe_approvals.sh")
    System.halt(2)
end
