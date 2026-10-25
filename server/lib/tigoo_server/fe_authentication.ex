defmodule TigooServer.FeAuthentication do
  @moduledoc "Seed challenges for electronic invoicing certificate authentication."

  @doc "Generates a padded Base64 seed matching the PDF example's size and a UTC timestamp."
  def new_seed do
    %{
      valor: :crypto.strong_rand_bytes(112) |> Base.encode64(),
      fecha: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      version: "1.0"
    }
  end
end
