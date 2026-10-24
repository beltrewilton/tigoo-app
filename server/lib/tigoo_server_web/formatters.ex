defmodule TigooServerWeb.Formatters do
  @moduledoc false

  import Phoenix.HTML, only: [html_escape: 1]
  alias Phoenix.HTML.Safe

  def money(value) do
    raw = decimal(value)

    [
      ~s(<span data-money="),
      Safe.to_iodata(html_escape(:erlang.float_to_binary(raw, decimals: 4))),
      ~s(" class="localized-money">),
      Safe.to_iodata(html_escape(money_text(raw))),
      "</span>"
    ]
    |> Phoenix.HTML.raw()
  end

  def money_text(value) do
    value = Float.round(decimal(value), 2)
    sign = if value < 0, do: "-", else: ""
    [whole, cents] = :erlang.float_to_binary(abs(value), decimals: 2) |> String.split(".")

    grouped =
      whole
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    "#{sign}$ #{grouped}.#{cents}"
  end

  def decimal(%Decimal{} = value), do: Decimal.to_float(value)
  def decimal(value) when is_number(value), do: value * 1.0

  def decimal(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> 0.0
    end
  end

  def decimal(_), do: 0.0
end
