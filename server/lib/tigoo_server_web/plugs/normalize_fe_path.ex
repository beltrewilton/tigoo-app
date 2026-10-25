defmodule TigooServerWeb.Plugs.NormalizeFePath do
  @moduledoc false

  @path ["fe", "autenticacion", "api", "semilla"]

  def init(opts), do: opts

  def call(conn, _opts) do
    if Enum.map(conn.path_info, &String.downcase/1) == @path do
      %{conn | path_info: @path, request_path: "/fe/autenticacion/api/semilla"}
    else
      conn
    end
  end
end
