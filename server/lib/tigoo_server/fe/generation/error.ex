defmodule TigooServer.Fe.Generation.Error do
  @moduledoc "An actionable generation failure, with optional source row and field."
  defexception [:message, :stage, :row, :field]
  @type t :: %__MODULE__{message: String.t() | nil, stage: atom() | nil,
    row: pos_integer() | nil, field: String.t() | nil}

  def fail!(stage, message, context \\ []) do
    location = Enum.flat_map([row: context[:row], field: context[:field]], fn
      {_, nil} -> []
      {key, value} -> ["#{key}=#{value}"]
    end)

    raise __MODULE__, stage: stage, row: context[:row], field: context[:field],
      message: Enum.join(["#{stage}: #{message}" | location], " ")
  end
end
