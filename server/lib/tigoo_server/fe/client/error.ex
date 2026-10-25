defmodule TigooServer.Fe.Client.Error do
  @moduledoc "A DGII client failure. `uncertain` means a document POST may have reached DGII."
  defexception [:message, :operation, :http_status, :details, uncertain: false]
  @type t :: %__MODULE__{message: String.t() | nil, operation: atom() | nil,
    http_status: integer() | nil, details: term(), uncertain: boolean()}
end
