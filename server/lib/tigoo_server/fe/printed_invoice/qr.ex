defmodule TigooServer.Fe.PrintedInvoice.Qr do
  @moduledoc "Pure-Elixir QR SVG generation with capacity checks before forcing a version."
  alias TigooServer.Fe.Generation.Error

  def svg!(payload, opts \\ []), do: render!(payload, opts).svg

  def render!(payload, opts \\ []) when is_binary(payload) do
    policy = Keyword.get(opts, :qr_version, "8")
    unless policy in ["8", "auto"], do: Error.fail!(:options, "qr_version must be 8 or auto")
    # qqr 0.2.0 validates capacity only when it selects the version itself.
    # Never call its forced-version path until this checked encoding succeeds.
    automatic = encode!(payload, ec_level: :low)
    required = div(automatic.width - 17, 4)
    if required > 8 and policy == "8" do
      Error.fail!(:qr, "DGII URL is #{byte_size(payload)} bytes and needs QR version #{required} in this encoder; version 8 cannot hold it. No PDF batch published. Use --qr-version auto only if the larger version is acceptable for your certification; XML/URL values must not be truncated or changed.")
    end
    version = max(required, 8)
    matrix = if required < 8, do: encode!(payload, version: 8, ec_level: :low), else: automatic
    unless matrix.width == 17 + 4 * version and matrix.height == matrix.width,
      do: Error.fail!(:qr, "Unexpected QR matrix dimensions")
    %{version: version, svg: QQR.SVG.render(matrix, quiet_zone: 4, module_size: 4,
      color: "#000000", background: "#ffffff", dot_shape: :square, finder_shape: :square)}
  end

  defp encode!(payload, opts) do
    case QQR.encode(payload, opts) do
      {:ok, matrix} -> matrix
      {:error, reason} -> Error.fail!(:qr, "Cannot encode DGII QR URL: #{reason}")
    end
  end
end
