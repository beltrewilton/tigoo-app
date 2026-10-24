alias TigooServer.Repo

tenants = ["sales_seed_test", "sales_other_test"]

# This script runs before ExUnit starts. Tenant migrations may open additional
# repository connections, so they must not run inside an ExUnit SQL sandbox.
Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

tenant_exists? = fn tenant ->
  {:ok, result} =
    Repo.query("SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = $1)", [tenant])

  [[exists?]] = result.rows
  exists?
end

Enum.each(tenants, fn tenant ->
  unless tenant_exists?.(tenant) do
    {:ok, _} =
      Triplex.create_schema(tenant, Repo, fn created_tenant, repo ->
        Triplex.migrate(created_tenant, repo)
      end)
  end

  {:ok, _} = Triplex.migrate(tenant, Repo)
end)
