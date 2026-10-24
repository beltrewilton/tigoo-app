defmodule TigooServer.Addons.Installer do
  @moduledoc """
  Discovery and loading boundary for local add-ons.

  Add-on source remains outside the Phoenix project. The host discovers add-ons
  by scanning the configured add-ons root for `*/addon.ex` and only accepts safe
  identifier-shaped directory names.
  """

  alias TigooServer.Addons

  @supported_events %{
    :sale_completed => "sale_completed",
    "sale_completed" => "sale_completed"
  }

  def available do
    case addons_root() do
      {:ok, root} ->
        root
        |> discovered_sources()
        |> Enum.map(fn {identifier, _path} -> identifier end)

      {:error, _reason} ->
        []
    end
  end

  def catalog do
    case addons_root() do
      {:ok, root} ->
        root
        |> discovered_sources()
        |> Enum.flat_map(fn {identifier, path} ->
          case catalog_entry(identifier, path) do
            {:ok, addon} -> [addon]
            {:error, _reason} -> []
          end
        end)
        |> Enum.sort_by(& &1.name)

      {:error, _reason} ->
        []
    end
  end

  def install(identifier, tenant) when is_binary(tenant) and tenant != "" do
    if Addons.installed?(identifier, tenant),
      do: :ok,
      else: discover_load_and_register(identifier, tenant)
  end

  def install(_identifier, _tenant), do: {:error, :missing_tenant}

  def uninstall(identifier, tenant) do
    case Addons.get_enabled_for(identifier, tenant) do
      nil -> {:error, :unknown_addon}
      addon -> unload_and_unregister(addon)
    end
  end

  def handler(addon) do
    with {:ok, path} <- source_path(addon.identifier),
         true <- File.regular?(path),
         handler <- revision_module(addon.identifier, addon.tenant, addon.revision),
         true <- addon.handler == Atom.to_string(handler),
         true <- ensure_entrypoint(path, handler) do
      {:ok, handler}
    else
      false -> {:error, :invalid_addon_handler}
      {:error, reason} -> {:error, reason}
    end
  rescue
    ArgumentError -> {:error, :invalid_addon_handler}
  end

  defp discover_load_and_register(identifier, tenant) do
    with {:ok, path} <- source_path(identifier),
         true <- File.regular?(path),
         {:ok, source} <- File.read(path),
         revision <- revision_for(source),
         handler <- revision_module(identifier, tenant, revision),
         modules when is_list(modules) <- compile_source(source, path, handler),
         {:ok, module} <- addon_module(modules),
         manifest when is_map(manifest) <- module.manifest(),
         :ok <- validate_manifest(manifest, identifier, handler),
         {:ok, _addon} <- Addons.register(registration_attrs(manifest, tenant, revision, handler)) do
      :ok
    else
      false -> {:error, :missing_addon_source}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_addon, other}}
    end
  end

  defp unload_and_unregister(addon) do
    handler = revision_module(addon.identifier, addon.tenant, addon.revision)

    if addon.handler == Atom.to_string(handler) do
      # Source files may define nested helper modules. Unload leaves before
      # their root namespace, always using soft_purge/1 (never purge/1).
      case safely_unload_namespace(handler) do
        :purged -> unregister(addon, :purged)
        :still_referenced -> unregister(addon, :still_referenced)
      end
    else
      {:error, :invalid_addon_handler}
    end
  end

  defp safely_unload_namespace(handler) do
    handler
    |> namespace_modules()
    |> Enum.reduce(:purged, fn module, status ->
      case safely_unload(module) do
        :purged -> status
        :still_referenced -> :still_referenced
      end
    end)
  end

  defp namespace_modules(handler) do
    namespace = Atom.to_string(handler)

    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(fn module ->
      module_name = Atom.to_string(module)
      module_name == namespace or String.starts_with?(module_name, namespace <> ".")
    end)
    |> Enum.sort_by(&(Atom.to_string(&1) |> byte_size()), :desc)
  end

  defp safely_unload(handler) do
    case :code.is_loaded(handler) do
      false ->
        :purged

      _loaded ->
        # A previous replacement may have left old code behind. Do not delete
        # the current version unless that old version can be safely removed.
        if :code.soft_purge(handler) and :code.delete(handler) do
          if :code.soft_purge(handler), do: :purged, else: :still_referenced
        else
          :still_referenced
        end
    end
  end

  defp unregister(addon, unload_status) do
    case Addons.unregister(addon) do
      {:ok, _addon} -> {:ok, unload_status}
      {:error, reason} -> {:error, reason}
    end
  end

  # Reload only when an installed add-on exposes an older host contract.
  # Normal requests do not recompile the external source.
  defp ensure_entrypoint(path, handler) do
    if function_exported?(handler, :render, 1) do
      true
    else
      compile_revision(path, handler)
      function_exported?(handler, :render, 1)
    end
  end

  defp compile_revision(path, handler) do
    with {:ok, source} <- File.read(path) do
      compile_source(source, path, handler)
    else
      _ -> []
    end
  end

  defp compile_source(source, path, handler) do
    source
    |> rewrite_root_module(handler)
    |> Code.compile_string(path)
  end

  defp rewrite_root_module(source, handler) do
    Regex.replace(~r/defmodule\s+[A-Za-z0-9_.]+\s+do/, source, "defmodule #{inspect(handler)} do",
      global: false
    )
  end

  defp revision_module(identifier, tenant, revision) do
    tenant_part =
      tenant |> String.replace(~r/[^a-zA-Z0-9]/, "_") |> Macro.camelize() |> String.slice(0, 40)

    tenant_hash =
      :crypto.hash(:sha256, tenant) |> Base.encode16(case: :lower) |> String.slice(0, 10)

    addon_part = identifier |> String.replace(~r/[^a-zA-Z0-9]/, "_") |> Macro.camelize()
    revision_part = revision |> String.replace("-", "")

    Module.concat([
      # Keep the persisted add-on namespace stable across host renames.
      "PosServer",
      :TenantAddons,
      "Tenant#{tenant_part}#{tenant_hash}",
      "#{addon_part}Revision#{revision_part}"
    ])
  end

  # Reinstalling unchanged source reuses its module name. A code change gets a
  # new immutable revision namespace, limiting new atoms to real source versions.
  defp revision_for(source) do
    :crypto.hash(:sha256, source)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp source_path(identifier) do
    with true <- valid_identifier?(identifier),
         {:ok, root} <- addons_root() do
      path = Path.join([root, identifier, "addon.ex"])

      if File.regular?(path), do: {:ok, path}, else: {:error, :unknown_addon}
    else
      false -> {:error, :unknown_addon}
      {:error, reason} -> {:error, reason}
    end
  end

  defp discovered_sources(root) do
    root
    |> Path.join("*/addon.ex")
    |> Path.wildcard()
    |> Enum.map(fn path -> {path |> Path.dirname() |> Path.basename(), path} end)
    |> Enum.filter(fn {identifier, _path} -> valid_identifier?(identifier) end)
  end

  defp valid_identifier?(identifier) when is_binary(identifier),
    do: Regex.match?(~r/\A[a-zA-Z0-9_]+\z/, identifier)

  defp valid_identifier?(_identifier), do: false

  defp addons_root do
    case System.get_env("ADDONS_PATH") do
      path when is_binary(path) and path != "" -> {:ok, Path.expand(path)}
      _ -> {:error, :missing_addons_path}
    end
  end

  defp catalog_entry(identifier, path) do
    with {:ok, source} <- File.read(path),
         revision <- revision_for(source),
         handler <- revision_module(identifier, "__catalog__", revision),
         modules when is_list(modules) <- compile_source(source, path, handler),
         {:ok, module} <- addon_module(modules),
         manifest when is_map(manifest) <- module.manifest(),
         :ok <- validate_manifest(manifest, identifier, handler) do
      {:ok,
       %{
         identifier: manifest.identifier,
         path: path,
         name: manifest.name,
         icon: manifest.icon,
         route: "/pos/addons/" <> manifest.identifier,
         description: Map.get(manifest, :description, "Add-on for this workspace."),
         events: normalized_events(manifest)
       }}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_addon, other}}
    end
  end

  defp addon_module(modules) do
    case Enum.find(modules, fn {module, _binary} -> function_exported?(module, :manifest, 0) end) do
      {module, _binary} -> {:ok, module}
      nil -> {:error, :missing_manifest}
    end
  end

  defp validate_manifest(
         %{identifier: manifest_identifier, route: route, handler: manifest_handler} = manifest,
         identifier,
         handler
       )
       when is_atom(manifest_handler) do
    if manifest_identifier == identifier and manifest_handler == handler and
         route in ["/pos/addons/" <> identifier, "/addons/" <> identifier] do
      with {:ok, _events} <- validate_events(manifest) do
        :ok
      end
    else
      {:error, :invalid_manifest}
    end
  end

  defp validate_manifest(_, _, _), do: {:error, :invalid_manifest}

  defp validate_events(manifest) do
    events = Map.get(manifest, :events, [])

    if is_list(events) do
      events
      |> Enum.reduce_while({:ok, []}, fn event, {:ok, acc} ->
        case Map.fetch(@supported_events, event) do
          {:ok, event_name} -> {:cont, {:ok, [event_name | acc]}}
          :error -> {:halt, {:error, :unsupported_addon_event}}
        end
      end)
      |> case do
        {:ok, events} -> {:ok, events |> Enum.reverse() |> Enum.uniq()}
        error -> error
      end
    else
      {:error, :invalid_addon_events}
    end
  end

  defp normalized_events(manifest) do
    case validate_events(manifest) do
      {:ok, events} -> events
      {:error, _reason} -> []
    end
  end

  defp registration_attrs(manifest, tenant, revision, handler) do
    %{
      identifier: manifest.identifier,
      name: manifest.name,
      route: "/pos/addons/" <> manifest.identifier,
      icon: manifest.icon,
      handler: Atom.to_string(handler),
      tenant: tenant,
      revision: revision,
      events: normalized_events(manifest),
      installed: true,
      enabled: true,
      installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end
end
