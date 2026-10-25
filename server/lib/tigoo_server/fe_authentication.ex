defmodule TigooServer.FeAuthentication do
  @moduledoc "Seed challenges for electronic invoicing certificate authentication."

  @doc "Generates a seed value using the RFC 6750 bearer character set and a UTC timestamp."
  def new_seed do
    %{
      valor: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      fecha: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      version: "1.0"
    }
  end
end
