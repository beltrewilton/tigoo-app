defmodule TigooServerWeb.EcfSaleComponents do
  use TigooServerWeb, :html
  alias TigooServer.Fe.SaleFiscal
  attr :details, :map, required: true
  attr :sequence, :string, required: true
  attr :cart, :list, required: true
  attr :line_options, :map, required: true
  attr :customer, :any, default: nil

  def ecf_sale_details(assigns) do
    ~H"""
    <section class="ecf-sale-details" aria-label="Electronic invoice details">
      <p class="field-description">Amounts are in DOP. Catalog prices include 18% ITBIS; fiscal prices are recalculated for the selected tax treatment.</p>
      <form id="ecf-buyer-details" class="form" phx-change="change_ecf_details" phx-submit="change_ecf_details">
        <div class="ecf-sale-fields">
          <label>Buyer identification
            <select class="input" name="ecf[ecf_buyer_kind]">
              <option value="domestic" selected={@details["ecf_buyer_kind"] == "domestic"}>RNC / Cédula</option>
              <option :if={@sequence not in ~w(TEST_E31 TEST_E45)} value="foreign" selected={@details["ecf_buyer_kind"] == "foreign"}>Foreign identifier</option>
            </select>
          </label>
          <label>Buyer identifier
            <input class="input" name="ecf[ecf_buyer_id]" maxlength="20" phx-debounce="300"
              value={@details["ecf_buyer_id"]} placeholder={@customer && @customer.document_id} />
          </label>
          <label>Buyer legal name
            <input class="input" name="ecf[ecf_buyer_name]" maxlength="150" phx-debounce="300"
              value={@details["ecf_buyer_name"]} placeholder={@customer && @customer.name} />
          </label>
          <label>Buyer address
            <input class="input" name="ecf[ecf_buyer_address]" maxlength="100" phx-debounce="300"
              value={@details["ecf_buyer_address"]} placeholder={@customer && @customer.address} />
          </label>
          <label>Income type
            <select class="input" name="ecf[ecf_income_type]">
              <option :for={{code, label} <- [{"01", "Operations"}, {"02", "Financial"}, {"03", "Extraordinary"}, {"04", "Rental"}, {"05", "Depreciable asset sale"}, {"06", "Other"}]}
                value={code} selected={@details["ecf_income_type"] == code}>{code} · {label}</option>
            </select>
          </label>
          <label :if={@sequence == "TEST_E46"}>Buyer country
            <input class="input" name="ecf[ecf_buyer_country]" maxlength="60" phx-debounce="300" value={@details["ecf_buyer_country"]} required />
          </label>
          <label :if={@sequence == "TEST_E46"}>Destination country
            <input class="input" name="ecf[ecf_destination_country]" maxlength="60" phx-debounce="300" value={@details["ecf_destination_country"]} required />
          </label>
        </div>
        <div :if={@sequence in ~w(TEST_E44 TEST_E45)}>
          <input type="hidden" name="ecf[ecf_buyer_confirmed]" value="false" />
          <label><input type="checkbox" name="ecf[ecf_buyer_confirmed]" value="true"
            checked={@details["ecf_buyer_confirmed"] == "true"} />
            {if @sequence == "TEST_E44", do: "I confirm this buyer qualifies for the special-regime exemption (including an eligible foreign diplomatic buyer).", else: "I confirm this buyer is an eligible government entity."}
          </label>
        </div>
        <div :if={@sequence == "TEST_E46"}>
          <input type="hidden" name="ecf[ecf_export_confirmed]" value="false" />
          <label><input type="checkbox" name="ecf[ecf_export_confirmed]" value="true"
            checked={@details["ecf_export_confirmed"] == "true"} />
            I confirm this goods sale qualifies as an export or eligible commercial free-zone transaction.
          </label>
          <p class="field-description">Exports use zero-rate ITBIS. Invoice services and separate delivery charges separately.</p>
        </div>
      </form>
      <details>
        <summary>Item tax and goods/service classification</summary>
        <form id="ecf-line-details" phx-change="change_ecf_lines" phx-submit="change_ecf_lines">
          <div :for={line <- @cart} class="ecf-sale-line">
            <span>{line.name}</span>
            <label>ITBIS
              <select class="input" name={"ecf_lines[#{line.id}][tax]"} disabled={@sequence in ~w(TEST_E44 TEST_E46)}>
                <option :for={{code, label} <- [{"1", "18%"}, {"2", "16%"}, {"3", "0%"}, {"4", "Exempt"}]}
                  value={code} selected={SaleFiscal.indicator(@sequence, get_in(@line_options, [to_string(line.id), "tax"]) || "1") == code}>{label}</option>
              </select>
            </label>
            <label>Item type
              <select class="input" name={"ecf_lines[#{line.id}][kind]"}>
                <option value="1" selected={(get_in(@line_options, [to_string(line.id), "kind"]) || "1") == "1"}>Goods</option>
                <option value="2" selected={get_in(@line_options, [to_string(line.id), "kind"]) == "2"}>Service</option>
              </select>
            </label>
          </div>
        </form>
      </details>
    </section>
    """
  end
end
