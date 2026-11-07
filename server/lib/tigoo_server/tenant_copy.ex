defmodule TigooServer.TenantCopy do
  @moduledoc "Copies a tenant into an independent test schema using employee login."

  require Logger

  alias TigooServer.{Repo, Tenants}
  alias TigooServer.Accounts.Scope

  @timeout :timer.minutes(15)

  def copy(scope, destination) when is_binary(destination) do
    destination = String.trim(destination)

    cond do
      not Scope.allowed?(scope, "company.settings") -> {:error, :forbidden}
      not Tenants.valid_identifier?(destination) -> {:error, :invalid_destination}
      destination == scope.tenant -> {:error, :same_tenant}
      not Tenants.exists?(scope.tenant) -> {:error, :source_unavailable}
      true -> copy_schema(scope.tenant, destination)
    end
  end

  def copy(_, _), do: {:error, :invalid_destination}

  defp copy_schema(source, destination) do
    result = Repo.transaction(fn ->
      query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
      query!("SET LOCAL search_path TO pg_catalog")
      query!("SET LOCAL lock_timeout = '10s'")

      if schema_exists?(destination), do: Repo.rollback(:destination_exists)
      tables = tables(source)
      validate_source!(source, tables)
      query!("CREATE SCHEMA #{quote_name(destination)}")

      # LIKE copies indexes, checks and generated expressions, but foreign keys
      # and defaults are rebuilt below so nothing points back to the source.
      Enum.each(tables, fn table ->
        query!("CREATE TABLE #{relation(destination, table)} (LIKE #{relation(source, table)} INCLUDING ALL EXCLUDING DEFAULTS EXCLUDING IDENTITY)")
      end)

      copy_sequences(source, destination)
      copy_defaults(source, destination)

      Enum.each(tables -- ["users_companies"], fn table ->
        columns = query!("""
        SELECT a.attname FROM pg_attribute a
        WHERE a.attrelid = $1::text::regclass AND a.attnum > 0
          AND NOT a.attisdropped AND a.attgenerated = ''
        ORDER BY a.attnum
        """, [relation(source, table)]).rows
        |> Enum.map_join(", ", fn [name] -> quote_name(name) end)

        query!("INSERT INTO #{relation(destination, table)} (#{columns}) SELECT #{columns} FROM #{relation(source, table)}")
      end)

      copy_foreign_keys(source, destination)
      isolate_integrations(destination)
      destination
    end, timeout: @timeout)

    case result do
      {:ok, tenant} ->
        :ok = Tenants.put(tenant)
        {:ok, tenant}
      error -> error
    end
  rescue
    error in Postgrex.Error ->
      Logger.error("Tenant copy failed: #{inspect(error.postgres[:code])}")

      if error.postgres[:code] in [:duplicate_schema, :duplicate_object],
        do: {:error, :destination_exists}, else: {:error, :copy_failed}
  end

  defp schema_exists?(tenant) do
    query!("SELECT 1 FROM pg_namespace WHERE nspname = $1", [tenant]).num_rows > 0
  end

  defp tables(source) do
    query!("""
    SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relkind = 'r' ORDER BY c.relname
    """, [source]).rows |> List.flatten()
  end

  defp validate_source!(source, tables) do
    unless Enum.all?(~w(company app_users app_user_store scopes schema_migrations), &(&1 in tables)),
      do: Repo.rollback(:source_unavailable)

    if query!("SELECT 1 FROM #{relation(source, "company")} WHERE is_test = TRUE LIMIT 1").num_rows > 0,
      do: Repo.rollback(:test_tenant)

    # Fail rather than silently lose objects not present in the application's
    # table-based tenant migrations (views, partitions, functions, triggers, RLS).
    unsupported = query!("""
    SELECT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = $1 AND (c.relkind NOT IN ('r', 'S', 'i') OR c.relrowsecurity OR c.relispartition)
      UNION ALL
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = $1
      UNION ALL
      SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = $1 AND NOT t.tgisinternal
      UNION ALL
      SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
      WHERE n.nspname = $1 AND t.typtype IN ('e', 'd', 'r', 'm')
    )
    """, [source]).rows
    if unsupported == [[true]], do: Repo.rollback(:unsupported_schema)

    unless query!("""
    SELECT 1 FROM #{relation(source, "app_users")} u
    JOIN #{relation(source, "app_user_store")} us ON us.user_id = u.id
    JOIN #{relation(source, "app_store")} s ON s.id = us.store_id
    WHERE u.is_active = 1 AND u.password IS NOT NULL AND u.password <> '' LIMIT 1
    """).num_rows > 0,
      do: Repo.rollback(:no_active_employees)
  end

  defp copy_sequences(source, destination) do
    query!("""
    SELECT c.relname, s.seqstart, s.seqincrement, s.seqmin, s.seqmax, s.seqcache, s.seqcycle,
           t.relname, a.attname
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_sequence s ON s.seqrelid = c.oid
    LEFT JOIN pg_depend d ON d.classid = 'pg_class'::regclass AND d.objid = c.oid
      AND d.refclassid = 'pg_class'::regclass AND d.deptype IN ('a', 'i')
    LEFT JOIN pg_class t ON t.oid = d.refobjid
    LEFT JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
    WHERE n.nspname = $1
    """, [source]).rows
    |> Enum.each(fn [name, start, increment, minimum, maximum, cache, cycle, table, column] ->
      sequence = relation(destination, name)
      query!("CREATE SEQUENCE #{sequence} START WITH #{start} INCREMENT BY #{increment} MINVALUE #{minimum} MAXVALUE #{maximum} CACHE #{cache} #{if cycle, do: "CYCLE", else: "NO CYCLE"}")
      [[value, called]] = query!("SELECT last_value, is_called FROM #{relation(source, name)}").rows
      query!("SELECT setval($1::text::regclass, $2, $3)", [sequence, value, called])

      if table && column do
        query!("ALTER SEQUENCE #{sequence} OWNED BY #{relation(destination, table)}.#{quote_name(column)}")
        query!("ALTER TABLE #{relation(destination, table)} ALTER COLUMN #{quote_name(column)} SET DEFAULT nextval('#{String.replace(sequence, "'", "''")}'::regclass)")
      end
    end)
  end

  defp copy_defaults(source, destination) do
    query!("""
    SELECT c.relname, a.attname, pg_get_expr(d.adbin, d.adrelid),
           pg_get_serial_sequence(format('%I.%I', n.nspname, c.relname), a.attname)
    FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
    JOIN pg_class c ON c.oid = d.adrelid JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND a.attgenerated = ''
    """, [source]).rows
    |> Enum.each(fn [table, column, expression, sequence] ->
      # Owned sequence defaults were already installed with destination names.
      if is_nil(sequence) do
        if String.contains?(expression, [source <> ".", quote_name(source) <> ".", "regclass"]),
          do: Repo.rollback(:unsupported_schema)
        query!("ALTER TABLE #{relation(destination, table)} ALTER COLUMN #{quote_name(column)} SET DEFAULT #{expression}")
      end
    end)
  end

  defp copy_foreign_keys(source, destination) do
    query!("""
    SELECT c.relname, k.conname, pg_get_constraintdef(k.oid), rn.nspname, r.relname,
           format('%I.%I', rn.nspname, r.relname)
    FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_class r ON r.oid = k.confrelid JOIN pg_namespace rn ON rn.oid = r.relnamespace
    WHERE n.nspname = $1 AND k.contype = 'f'
    """, [source]).rows
    |> Enum.each(fn [table, name, definition, referenced_schema, referenced_table, reference] ->
      unless referenced_schema == source or {referenced_schema, referenced_table} == {"public", "users"},
        do: Repo.rollback(:unsupported_schema)

      definition = if referenced_schema == source do
        target = "REFERENCES #{reference}("
        unless String.contains?(definition, target), do: Repo.rollback(:unsupported_schema)
        String.replace(definition, target, "REFERENCES #{relation(destination, referenced_table)}(", global: false)
      else
        definition
      end

      query!("ALTER TABLE #{relation(destination, table)} ADD CONSTRAINT #{quote_name(name)} #{definition}")
    end)
  end

  defp isolate_integrations(destination) do
    query!("""
    UPDATE #{relation(destination, "company")}
    SET is_test = TRUE, access_token = NULL, connected = FALSE, odoo_url = NULL, odoo_db = NULL,
        odoo_user = NULL, odoo_apikey = NULL, ecf_test_sequences_ready = FALSE
    """)
    query!("UPDATE #{relation(destination, "app_users")} SET ecf_test_enabled = FALSE")
    query!("""
    UPDATE #{relation(destination, "fe_test_invoices")}
    SET snapshot = snapshot - 'batch_path',
        state = CASE WHEN state IN ('queued', 'pending') THEN 'unknown' ELSE state END,
        error = 'Copied tenant: fiscal artifacts and automatic submission are disabled.'
    """)
    # Addons and signing files are deliberately not copied: both have their own
    # tenant-specific installation/configuration outside the tenant schema.
  end

  defp relation(schema, table), do: quote_name(schema) <> "." <> quote_name(table)
  defp quote_name(name), do: "\"" <> String.replace(name, "\"", "\"\"") <> "\""
  defp query!(sql, params \\ []), do: Repo.query!(sql, params, timeout: @timeout)
end
