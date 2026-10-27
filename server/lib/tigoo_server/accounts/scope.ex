defmodule TigooServer.Accounts.Scope do
  @moduledoc """
  Request authorization scope. Tenant-owned contexts receive this scope from
  the authentication plug instead of accepting a tenant from request params.
  """

  alias TigooServer.Accounts.User

  defstruct user: nil,
            store_id: nil,
            tenant: nil,
            actor: nil,
            actor_id: nil,
            login: nil,
            pic: nil,
            ecf_test_enabled: false,
            store_ids: [],
            scopes: []

  @doc "Creates a scope for an authenticated user; returns nil when absent."
  def for_user(%User{} = user), do: for_user(user, [])
  def for_user(nil), do: nil

  def for_user(%User{} = user, opts) do
    %__MODULE__{
      user: %{name: user.name, tenant: user.tenant},
      tenant: user.tenant,
      actor: :admin,
      actor_id: user.id,
      login: user.email,
      pic: user.google_picture_url,
      store_id: Keyword.get(opts, :store_id),
      scopes: :admin
    }
  end

  def admin?(%__MODULE__{actor: :admin}), do: true
  def admin?(_), do: false

  def allowed?(%__MODULE__{actor: :admin}, _permission), do: true
  def allowed?(scope, _permission) when is_map(scope) and scope.scopes == :admin, do: true
  def allowed?(%__MODULE__{scopes: scopes}, permission), do: permission in scopes
  def allowed?(_, _), do: false
end
