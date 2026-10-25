defmodule TigooServerWeb.Plugs.NormalizeFePath do
  @moduledoc false

  @paths [
    ["fe", "autenticacion", "api", "semilla"],
    ["fe", "autenticacion", "api", "validacioncertificado"],
    ["fe", "recepcion", "api", "ecf"]
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    path = Enum.map(conn.path_info, fn part ->
      normalized = part |> URI.decode() |> String.normalize(:nfc) |> String.downcase()
      if normalized == "recepción", do: "recepcion", else: normalized
    end)

    if path in @paths do
      %{conn | path_info: path, request_path: "/" <> Enum.join(path, "/")}
    else
      conn
    end
  end
end
