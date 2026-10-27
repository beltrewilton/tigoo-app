defmodule TigooServer.Retaily.CompanySettings do
  @moduledoc false

  import Ecto.Query

  alias TigooServer.{Repo, TenantContext}
  alias TigooServer.Accounts.{Company, UserCompany}
  alias TigooServer.Retaily.{BusinessTime, Inventory, Pricing, PricingList, Product, Provider, Sequence, Store}
  alias TigooServer.Retaily.SequenceRotation

  def overview(scope) do
    tenant = TenantContext.tenant!()

    {:ok,
     %{
       company: company(scope),
       ecf_test: ecf_test_settings(tenant),
       price_lists: list_price_lists(tenant),
       stores: list_stores(tenant),
       sequence_sets: list_sequence_sets(tenant),
       providers: list_providers(tenant)
     }}
  end

  defp ecf_test_settings(tenant) do
    case Repo.all(from(c in Company, where: c.active == true, limit: 2), prefix: tenant) do
      [company] -> Map.take(company, [:address, :ecf_test_sequence_expiry, :ecf_test_sequences_ready])
      _ -> nil
    end
  end

  def update_ecf_test_settings(scope, attrs) do
    if TigooServer.Accounts.Scope.allowed?(scope, "company.settings") do
      Repo.transaction(fn ->
        company = case Repo.all(from(c in Company, where: c.active == true, limit: 2, lock: "FOR UPDATE"), prefix: scope.tenant) do
          [company] -> company
          _ -> Repo.rollback(:company_unavailable)
        end
        changeset = company
          |> Ecto.Changeset.cast(attrs, [:address, :ecf_test_sequence_expiry, :ecf_test_sequences_ready])
          |> Ecto.Changeset.update_change(:address, &String.trim/1)
          |> Ecto.Changeset.validate_length(:address, max: 100)
        changeset = if Ecto.Changeset.get_field(changeset, :ecf_test_sequences_ready) do
          changeset = Ecto.Changeset.validate_required(changeset, [:address, :ecf_test_sequence_expiry])
          case Ecto.Changeset.get_field(changeset, :ecf_test_sequence_expiry) do
            %Date{} = expiry ->
              today = DateTime.utc_now() |> DateTime.add(-14_400) |> DateTime.to_date()
              if Date.compare(expiry, today) == :lt,
                do: Ecto.Changeset.add_error(changeset, :ecf_test_sequence_expiry, "has expired"), else: changeset
            _ -> changeset
          end
        else
          changeset
        end
        case Repo.update(changeset, prefix: scope.tenant) do
          {:ok, company} -> Map.take(company, [:address, :ecf_test_sequence_expiry, :ecf_test_sequences_ready])
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    else
      {:error, :forbidden}
    end
  end

  def create_price_list(scope, attrs), do: save_price_list(scope, %Pricing{}, attrs)

  def update_brand_logo(scope, attrs) do
    tenant = TenantContext.tenant!()

    with %Company{} = company <- editable_company(scope, tenant) do
      company
      |> Ecto.Changeset.cast(attrs, [:brand_logo])
      |> Ecto.Changeset.validate_format(:brand_logo, ~r/^data:image\/[a-zA-Z0-9.+-]+;base64,/,
        message: "must be an image encoded as Base64"
      )
      |> Repo.update(prefix: tenant)
      |> write_result()
    else
      nil -> {:error, :not_found}
    end
  end

  defp editable_company(%{actor: :admin} = scope, tenant) do
    %{id: company_id} = company(scope)
    Repo.get(Company, company_id, prefix: tenant)
  end

  defp editable_company(_scope, tenant) do
    Repo.one(from(company in Company, limit: 1), prefix: tenant)
  end

  def update_price_list(scope, id, attrs) do
    with %Pricing{} = pricing <- Repo.get(Pricing, id, prefix: TenantContext.tenant!()) do
      save_price_list(scope, pricing, attrs)
    else
      nil -> {:error, :not_found}
    end
  end

  def delete_price_list(id) do
    tenant = TenantContext.tenant!()

    Repo.transaction(fn ->
      case Repo.get(Pricing, id, prefix: tenant) do
        nil ->
          Repo.rollback(:not_found)

        pricing ->
          Repo.delete_all(from(entry in PricingList, where: entry.pricing_id == ^pricing.id),
            prefix: tenant
          )

          Repo.delete!(pricing, prefix: tenant)
      end
    end)
    |> transaction_result()
  end

  def create_store(scope, attrs), do: save_store(scope, %Store{}, attrs)

  def update_store(scope, id, attrs) do
    with %Store{} = store <- Repo.get(Store, id, prefix: TenantContext.tenant!()) do
      save_store(scope, store, attrs)
    else
      nil -> {:error, :not_found}
    end
  end

  def delete_store(id) do
    case Repo.get(Store, id, prefix: TenantContext.tenant!()) do
      nil -> {:error, :not_found}
      store -> Repo.delete(store, prefix: TenantContext.tenant!()) |> write_result()
    end
  end

  def create_sequence_set(_scope, attrs), do: save_sequence_set(%Sequence{}, attrs)

  @doc """
  Inserts a sequence rotation in the current tenant's schema.

  Returns `{:ok, sequence_rotation}` with the database-computed rotation values,
  or `{:error, changeset}`. Raises if the tenant context has not been set.
  """
  def create_sequence_rotation(attrs) do
    tenant = TenantContext.tenant!()

    %SequenceRotation{}
    |> SequenceRotation.changeset(attrs)
    |> Repo.insert(prefix: tenant)
  end

  def update_sequence_set(_scope, id, attrs) do
    case Repo.get(Sequence, id, prefix: TenantContext.tenant!()) do
      nil -> {:error, :not_found}
      sequence -> save_sequence_set(sequence, attrs)
    end
  end

  def delete_sequence_set(id) do
    case Repo.get(Sequence, id, prefix: TenantContext.tenant!()) do
      nil -> {:error, :not_found}
      sequence -> Repo.delete(sequence, prefix: TenantContext.tenant!()) |> write_result()
    end
  end

  def create_provider(_scope, attrs), do: save_provider(%Provider{}, attrs)

  def update_provider(_scope, id, attrs) do
    case Repo.get(Provider, id, prefix: TenantContext.tenant!()) do
      nil -> {:error, :not_found}
      provider -> save_provider(provider, attrs)
    end
  end

  def delete_provider(id) do
    case Repo.get(Provider, id, prefix: TenantContext.tenant!()) do
      nil -> {:error, :not_found}
      provider -> Repo.delete(provider, prefix: TenantContext.tenant!()) |> write_result()
    end
  end

  defp save_price_list(scope, pricing, attrs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    label = attrs["label"] || attrs[:label]

    values = %{
      label: label,
      price_key: price_key(label),
      user_modified: scope.user.name,
      status: 1,
      date_create: pricing.date_create || now
    }

    pricing
    |> Pricing.changeset(values)
    |> Repo.insert_or_update(prefix: TenantContext.tenant!())
    |> write_result()
  end

  defp save_store(scope, store, attrs) do
    company_id = company(scope).id

    values =
      Map.take(attrs, ["name", "address", "slogan", "logo"])
      |> Map.merge(%{
        "company_id" => to_string(company_id),
        "date_create" =>
          store.date_create || BusinessTime.local_now(TenantContext.tenant!())
      })

    tenant = TenantContext.tenant!()
    changeset = Store.changeset(store, values)

    if store.id do
      Repo.update(changeset, prefix: tenant) |> write_result()
    else
      Repo.transaction(fn ->
        with {:ok, created} <- Repo.insert(changeset, prefix: tenant),
             {_, _} <- initialize_store_inventory(created.id, scope.user.name, tenant) do
          created
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
      |> transaction_result()
    end
  end

  defp initialize_store_inventory(store_id, username, tenant) do
    now = BusinessTime.local_now(tenant)

    rows =
      Repo.all(
        from(product in Product,
          select: %{
            product_id: product.id,
            store_id: type(^store_id, :integer),
            quantity: 0,
            prev_quantity: 0,
            last_update: type(^now, :naive_datetime),
            user_updated: type(^username, :string)
          }
        ),
        prefix: tenant
      )

    if rows == [],
      do: {0, nil},
      else:
        Repo.insert_all(Inventory, rows,
          prefix: tenant,
          on_conflict: :nothing,
          conflict_target: [:product_id, :store_id]
        )
  end

  defp save_sequence_set(sequence, attrs) do
    sequence
    |> Sequence.changeset(
      Map.take(attrs, ["name", "code", "prefix", "fill", "increment_by", "current_seq"])
    )
    |> Repo.insert_or_update(prefix: TenantContext.tenant!())
    |> write_result()
  end

  defp save_provider(provider, attrs) do
    values =
      Map.take(attrs, ["name"])
      |> Map.put(
        "date_create",
        provider.date_create || NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      )

    provider
    |> Provider.changeset(values)
    |> Repo.insert_or_update(prefix: TenantContext.tenant!())
    |> write_result()
  end

  defp list_price_lists(tenant),
    do:
      Repo.all(
        from(pricing in Pricing,
          order_by: [asc: pricing.label],
          select: %{
            id: pricing.id,
            label: pricing.label,
            price_key: pricing.price_key,
            status: pricing.status
          }
        ),
        prefix: tenant
      )

  defp list_stores(tenant),
    do:
      Repo.all(
        from(store in Store,
          order_by: [asc: store.name],
          select: %{
            id: store.id,
            name: store.name,
            address: store.address,
            slogan: store.slogan,
            logo: store.logo,
            company_id: store.company_id
          }
        ),
        prefix: tenant
      )

  defp list_sequence_sets(tenant),
    do:
      Repo.all(
        from(sequence in Sequence,
          order_by: [asc: sequence.code],
          select: %{
            id: sequence.id,
            name: sequence.name,
            code: sequence.code,
            prefix: sequence.prefix,
            fill: sequence.fill,
            increment_by: sequence.increment_by,
            current_seq: sequence.current_seq
          }
        ),
        prefix: tenant
      )

  defp list_providers(tenant),
    do:
      Repo.all(
        from(provider in Provider,
          order_by: [asc: provider.name],
          select: %{id: provider.id, name: provider.name}
        ),
        prefix: tenant
      )

  defp company(%{actor: :admin, actor_id: user_id}) do
    Repo.one(
      from(company in Company,
        join: membership in UserCompany,
        on: membership.company_id == company.id,
        where: membership.user_id == ^user_id,
        limit: 1,
        select: %{
          id: company.id,
          name: company.company_name,
          rnc: company.rnc,
          brand_logo: company.brand_logo
        }
      ),
      prefix: TenantContext.tenant!()
    ) || first_company(TenantContext.tenant!())
  end

  defp company(scope), do: %{id: scope.tenant, name: scope.tenant, rnc: nil, brand_logo: nil}

  defp first_company(tenant) do
    Repo.one(
      from(company in Company,
        limit: 1,
        select: %{
          id: company.id,
          name: company.company_name,
          rnc: company.rnc,
          brand_logo: company.brand_logo
        }
      ),
      prefix: tenant
    ) || %{id: tenant, name: tenant, rnc: nil, brand_logo: nil}
  rescue
    _ -> %{id: tenant, name: tenant, rnc: nil, brand_logo: nil}
  end

  defp price_key(label) when is_binary(label) do
    key =
      label
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "_")
      |> String.trim("_")

    if key == "", do: "price_list", else: key
  end

  defp price_key(_), do: "price_list"
  defp write_result({:ok, value}), do: {:ok, value}
  defp write_result({:error, value}), do: {:error, value}
  defp transaction_result({:ok, value}), do: {:ok, value}
  defp transaction_result({:error, value}), do: {:error, value}
end
