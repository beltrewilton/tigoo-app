defmodule TigooServer.FeAuthentication do
  @moduledoc "Seed challenges for electronic invoicing certificate authentication."

  @doc "Generates a padded Base64 seed matching the PDF example's size and a UTC timestamp."
  def new_seed do
    seed = %{
      valor: :crypto.strong_rand_bytes(112) |> Base.encode64(),
      fecha: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    case TigooServer.FeSeedStore.put(seed) do
      :ok -> {:ok, seed}
      error -> error
    end
  end

  @doc "Exchanges a verified, single-use signed seed for a one-hour FE access token."
  def validate_certificate(xml) do
    with {:ok, seed, identity} <- TigooServer.FeSignature.verify(xml),
         :ok <- TigooServer.FeSeedStore.consume(seed) do
      issued = DateTime.utc_now() |> DateTime.truncate(:second)
      expires = DateTime.add(issued, 3600, :second)
      claims = Map.put(identity, :expires_at, DateTime.to_unix(expires))
      token = Phoenix.Token.sign(TigooServerWeb.Endpoint, "fe-access", claims)

      {:ok, %{token: token, expira: DateTime.to_iso8601(expires), expedido: DateTime.to_iso8601(issued)}}
    end
  end

  @doc "Verifies an FE bearer token independently from tenant login tokens."
  def verify_token(token) when is_binary(token) do
    with {:ok, %{expires_at: expires} = identity} <-
           Phoenix.Token.verify(TigooServerWeb.Endpoint, "fe-access", token, max_age: 3600),
         true <- is_integer(expires) and expires > System.system_time(:second) do
      {:ok, identity}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def verify_token(_), do: {:error, :invalid_token}
end
