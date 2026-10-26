defmodule TigooServer.Fe.PrintedInvoice.Template do
  @moduledoc "Receipt-style, print-only HTML using signed fiscal values; no invented payment or SKU data."
  alias TigooServer.Fe.Generation.Xml
  @titles %{"31" => "Factura de Crédito Fiscal Electrónica", "32" => "Factura de Consumo Electrónica",
    "33" => "Nota de Débito Electrónica", "34" => "Nota de Crédito Electrónica",
    "41" => "Comprobante de Compras Electrónico", "43" => "Comprobante para Gastos Menores Electrónico",
    "44" => "Comprobante para Regímenes Especiales Electrónico", "45" => "Comprobante Gubernamental Electrónico",
    "46" => "Comprobante para Exportaciones Electrónico", "47" => "Comprobante para Pagos al Exterior Electrónico"}
  @totals [{"MontoGravadoTotal", "Subtotal gravado"}, {"MontoGravadoI1", "Base gravada 18%"}, {"MontoGravadoI2", "Base gravada 16%"},
    {"MontoGravadoI3", "Base gravada 0%"}, {"MontoExento", "Monto exento"},
    {"TotalITBIS1", "ITBIS 18%"}, {"TotalITBIS2", "ITBIS 16%"}, {"TotalITBIS3", "ITBIS 0%"},
    {"TotalITBIS", "Total ITBIS"}, {"MontoImpuestoAdicional", "Impuestos adicionales"}, {"MontoTotal", "TOTAL RD$"},
    {"MontoNoFacturable", "Monto no facturable"}, {"MontoPeriodo", "Monto período"},
    {"SaldoAnterior", "Saldo anterior"}, {"MontoAvancePago", "Avance de pago"},
    {"ValorPagar", "Valor a pagar"}, {"TotalITBISRetenido", "ITBIS retenido"},
    {"TotalISRRetencion", "ISR retenido"}, {"TotalITBISPercepcion", "ITBIS percibido"},
    {"TotalISRPercepcion", "ISR percibido"}]

  def page(receipts) do
    """
    <!doctype html><html lang="es"><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
    <title>Representaciones impresas e-CF</title><style>
    @page {size:A4; margin:12mm;} * {box-sizing:border-box;}
    body {margin:0;color:#111;background:white;font:11px 'Courier New',monospace;}
    .receipt {width:80mm;margin:0 auto;break-after:page;} .receipt:last-child {break-after:auto;}
    header, footer {text-align:center;} h1 {font-size:23px;letter-spacing:2px;margin:0 0 5px;}
    h2 {font-size:12px;margin:7px 0;} p {margin:3px 0;overflow-wrap:anywhere;}
    .logo {max-width:46mm;max-height:28mm;} .rule {border-top:1px dashed #555;margin:9px 0;}
    .pair {display:flex;justify-content:space-between;gap:8px;margin:4px 0;}
    .pair span:last-child {text-align:right;overflow-wrap:anywhere;}
    table {width:100%;border-collapse:collapse;table-layout:fixed;}
    th {font-weight:normal;border-bottom:1px dashed #555;} td,th {padding:4px 0;vertical-align:top;}
    .amount {text-align:right;white-space:nowrap;} .item {width:72%;overflow-wrap:anywhere;}
    .muted {font-size:10px;} .bold {font-weight:bold;} .qr {width:42mm;height:42mm;}
    .line {break-inside:avoid;} .fiscal {break-inside:avoid;} a {color:#111;}
    </style></head><body>#{Enum.join(receipts, "\n")}</body></html>
    """
  end

  def receipt(root, qr, code, logo) do
    header = Xml.child(root, "Encabezado")
    issuer = Xml.child(header, "Emisor")
    buyer = Xml.child(header, "Comprador")
    id = Xml.child(header, "IdDoc")
    totals = Xml.child(header, "Totales")
    type = Xml.value(id, ["TipoeCF"])
    items = root |> Xml.child("DetallesItems") |> Xml.children("Item")
    reference = Xml.child(root, "InformacionReferencia")
    payment = case Xml.value(id, ["TipoPago"]) do
      "1" -> "Contado"
      "2" -> "Crédito"
      "3" -> "Gratuito"
      other -> other
    end
    logo_html = if logo, do: "<img class=\"logo\" alt=\"Logo del emisor\" src=\"#{escape(logo)}\">", else: ""
    name = Xml.value(issuer, ["NombreComercial"]) || Xml.value(issuer, ["RazonSocialEmisor"])
    """
    <article class="receipt"><header>#{logo_html}<h1>#{escape(name)}</h1>
    <p>#{escape(Xml.value(issuer, ["RazonSocialEmisor"]))}</p>
    <p>#{escape(Xml.value(issuer, ["DireccionEmisor"]))}</p>
    <p>RNC: #{escape(Xml.value(issuer, ["RNCEmisor"]))}</p>
    #{optional(issuer, "Sucursal", "Sucursal")}
    #{optional(issuer, "CorreoEmisor", "Correo")}
    <h2>#{escape(Map.fetch!(@titles, type))}</h2><p>REPRESENTACIÓN IMPRESA e-CF</p></header>
    <div class="rule"></div>
    #{pair("e-NCF", Xml.value(id, ["eNCF"]))}
    #{optional(id, "FechaVencimientoSecuencia", "Vencimiento secuencia")}
    #{pair("Fecha emisión", Xml.value(issuer, ["FechaEmision"]))}
    #{optional(buyer, "RazonSocialComprador", "Cliente / contraparte")}
    #{optional(buyer, "RNCComprador", "RNC / Cédula")}
    #{optional(buyer, "IdentificadorExtranjero", "Identificación extranjera")}
    #{optional(buyer, "DireccionComprador", "Dirección contraparte")}
    #{pair("Condición de pago", payment)}
    #{optional(id, "FechaLimitePago", "Fecha límite de pago")}
    #{optional(reference, "NCFModificado", "e-NCF modificado")}
    #{optional(reference, "FechaNCFModificado", "Fecha comprobante original")}
    #{optional(reference, "RazonModificacion", "Motivo modificación")}
    <div class="rule"></div><table><thead><tr><th class="item">DESCRIPCIÓN</th><th class="amount">VALOR RD$</th></tr></thead>
    <tbody>#{Enum.map_join(items, "", &item/1)}</tbody></table>
    <p class="muted">#{if Xml.value(id, ["IndicadorMontoGravado"]) == "1", do: "Precios incluyen ITBIS.", else: "Importes según comprobante electrónico."}</p>
    <div class="rule"></div>
    #{Enum.map_join(@totals, "", fn {field, label} -> money_pair(totals, field, label) end)}
    #{adjustment_total(items, "DescuentoMonto", "Descuentos en artículos (incluidos)")}
    #{adjustment_total(items, "RecargoMonto", "Recargos en artículos (incluidos)")}
    #{pair("Líneas de artículos", Integer.to_string(length(items)))}
    #{payments(id)}
    <div class="rule"></div><footer class="fiscal">
    <img class="qr" src="#{escape(qr)}" alt="QR de consulta DGII">
    #{pair("Código de seguridad", code)}
    #{pair("Fecha firma digital", Xml.value(root, ["FechaHoraFirma"]))}
    <p>Moneda: pesos dominicanos (DOP)</p><p>Gracias por su compra</p>
    <p class="muted">Comprobante de simulación · CerteCF</p></footer></article>
    """
  end

  defp item(node) do
    indicator = Xml.value(node, ["IndicadorFacturacion"])
    tax = %{"0" => "No facturable", "1" => "ITBIS 18%", "2" => "ITBIS 16%", "3" => "ITBIS 0%", "4" => "Exento"}[indicator]
    kind = if Xml.value(node, ["IndicadorBienoServicio"]) == "2", do: "Servicio", else: "Bien"
    """
    <tr class="line"><td class="item">#{escape(Xml.value(node, ["NombreItem"]))}
    <p class="muted">#{escape(Xml.value(node, ["DescripcionItem"]))}</p>
    <p>#{escape(Xml.value(node, ["CantidadItem"]))} × RD$#{escape(Xml.value(node, ["PrecioUnitarioItem"]))}</p>
    <p class="muted">#{escape(kind)} · #{escape(tax)}</p>
    #{money_pair(node, "DescuentoMonto", "Descuento")}
    #{money_pair(node, "RecargoMonto", "Recargo")}
    </td><td class="amount">#{money(Xml.value(node, ["MontoItem"]))}</td></tr>
    """
  end

  defp payments(id) do
    table = Xml.child(id, "TablaFormasPago")
    if table do
      "<div class=\"rule\"></div>" <> Enum.map_join(Xml.children(table, "FormaDePago"), "", fn entry ->
        label = %{"1" => "Efectivo", "2" => "Cheque / transferencia / depósito", "3" => "Tarjeta débito/crédito",
          "4" => "Venta a crédito", "5" => "Bonos / certificados regalo", "6" => "Permuta", "7" => "Otras formas de pago"}[Xml.value(entry, ["FormaPago"])] || "Pago"
        money_pair(entry, "MontoPago", label)
      end)
    else
      ""
    end
  end

  defp adjustment_total(items, field, label) do
    sum = Enum.reduce(items, Decimal.new(0), fn item, acc -> Decimal.add(acc, Decimal.new(Xml.value(item, [field]) || "0")) end)
    if Decimal.compare(sum, 0) == :gt, do: pair(label, "RD$" <> money(Decimal.to_string(sum, :normal))), else: ""
  end
  defp optional(nil, _, _), do: ""
  defp optional(node, field, label), do: pair(label, Xml.value(node, [field]))
  defp money_pair(nil, _, _), do: ""
  defp money_pair(node, field, label) do
    if value = Xml.value(node, [field]), do: pair(label, "RD$" <> money(value)), else: ""
  end
  defp pair(_, nil), do: ""
  defp pair(label, value), do: "<div class=\"pair\"><span>#{escape(label)}</span><span>#{escape(value)}</span></div>"
  defp money(nil), do: ""
  defp money(value), do: value |> Decimal.new() |> Decimal.round(2) |> Decimal.to_string(:normal)
  defp escape(nil), do: ""
  defp escape(text), do: text |> to_string() |> String.replace("&", "&amp;") |> String.replace("<", "&lt;") |> String.replace(">", "&gt;") |> String.replace("\"", "&quot;") |> String.replace("'", "&#39;")
end
