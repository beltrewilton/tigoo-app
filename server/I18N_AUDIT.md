# LiveView i18n hard-coded text audit

Scope: user-facing Phoenix/LiveView, HEEx, controller template, static JS, and receipt-printer text under `server`.

## lib/tigoo_server_web/live/login_live.ex

- Page title: `Tigoo Sign in`
- Errors/status: `No store is available for this account.`, `Stores could not be loaded.`, `The username/email or password is incorrect.`, `Select a store to continue.`, `Google sign-in is available in the desktop or mobile app.`, `Unable to sign in.`
- Titles/copy: `Sign in`, `Use your username or email and password to continue.`
- Form labels/options/buttons: `Username or email`, `Password`, `Store`, `Select a store`, `Continue`, `Sign in`, `Continue with Google`

## lib/tigoo_server_web/components/pos_layout_components.ex

- Navigation aria labels: `Primary navigation`, `POS`, `Customers`, `Invoice report`, `Inventory`, `Purchase orders`, `Company settings`, `Users`
- Theme/store/user menu labels: `Choose theme`, `Theme`, `Default Light`, `Nature Light`, `Nature Dark`, `Caffeine Light`, `Caffeine Dark`, `Bold Tech Light`, `Bold Tech Dark`, `Doom 64 Light`, `Doom 64 Dark`, `Choose active store`, `Active store`, `Open menu for ...`, `User menu`
- Status/language UI: `System status`, `Change display language`, `English`, `Español`, `Português`, `Printer disconnected`, `Network connected`
- Loading labels: `Loading invoice details`, `Loading screen content`
- JS-updated labels in `priv/static/assets/theme.js`: `Expand navigation`, `Collapse navigation`

## lib/tigoo_server_web/live/pos_live.ex

- Page/status/error text: `Products could not be loaded.`, `Loading products…`, `No matching products.`, `Scroll for more products`, `products loaded`
- Catalog: `Catalog`, `Products`, `View sale`, `Add ...`, `Unnamed product`, `SKU`, `Tap to add`, `Stock`
- Customer picker: `Customers`, `Customer list`, `Crear client`, `Back`, `Search customers`, `Search customers by name or phone`, `No customers found.`, `Customer accounts and purchase activity.`, `Name`, `Document ID`, `Phone`, `Customer action`, `Choose`, `Choose: customer`
- Checkout: `Checkout`, `Customer`, `Payment & completion`, `Back to sale`, `Checkout progress`, `1. Customer`, `2. Payment`, `Pick a customer…`, `Back`, `Continue`, `Sequence type`, `Consumer final`, `Direct sale`, `Fiscal voucher`
- Delivery/credit/payment: `Delivery`, `Free amount`, `Delivery free amount`, `Select delivery free amount`, `Pay on Credit`, `Due date`, `Complete`, `Payments`, `Cash`, `Credit Card`, `Remove payment`, `Add payment`, `Remaining:`, `Change:`, `Memo (optional)`, `Up to 1000 characters.`
- Cart/order: `Current sale`, `View customer purchases`, `Pick a customer …`, `Clear customer`, `Close sale`, `Clear`, `Your order is empty. Select a product to begin.`, `Apply a discount to this item`, `off`, `Sub`, `Tax`, `Total`, `each`, `Remove ...`, `Decrease quantity`, `Item count`, `Increase quantity`, `Items`, `Subtotal`, `Tax (18%)`, `Discount`, `Delivery`, `Apply a discount to this sale`, `Apply order discount. Press Enter.`, `Payment method`
- Clear sale dialog: `Clear this order?`, `All items and line discounts will be removed.`, `Cancel`, `Clear order`
- Discount dialog: `Line item discount`, `Order discount`, `Apply a discount`, `Apply an order discount`, `Discount type`, `%`, `$`, `Discount percentage`, `Discount amount`, `Clear`, `Enter 0 to remove this item discount.`, `The amount applies to this entire order line.`, `Amount`, `After discount`, `Apply discount`, `Choose a percentage or amount for this order.`
- Customer purchases dialog: `recent purchases`, `The 10 most recent purchases, newest first.`, `Date`, `Salesperson`, `Items`, `Status`, `Item`, `Quantity`, `Price`, `Product #...`, `sale ...`, close button text
- Print prompt: `Sale completed`, `Would you like to print the receipt?`, `Print receipt`, `Skip`
- Amount sources: product cards use `product.price`; checkout/order totals use calculated `total(@socket)`, `subtotal(@socket)`, `tax(@socket)`, `items(@socket)`, `line_discount_total(@socket)`, `order_discount_total(@socket)`, `@delivery`, `remaining(@socket)`, `paid(@socket) - total(@socket)`.
- Line amount sources: cart `line.sub`, `line.tax`, `line.price`, `line.discount`, `line_gross(line) - line_discount(line)`, and `line_factor(line)`.
- Discount amount sources: `discount_base(assigns)`, `discount_preview(assigns)`, `@discount_input`, `@discount_type`; percent strings are built as `"#{line.discount}%"` and `"#{float(item.discount_input)}%"`.
- Payment amount sources: `payment.amount`, `paid(@socket)`, `remaining(@socket)`.
- Customer purchase amount sources: `purchase.amount`, item `price`, item `total`, item discount via `purchase_discount/1`.
- Formatting: private `money/1` rounds float, hard-codes `$`, comma thousands, dot decimal, and two cents: `"$#{whole_with_commas}.#{cents}"`.
- Locale flags: `$` button is a hard-coded currency symbol; `Tax (18%)` and 18% rate label are hard-coded; date formatting uses `Calendar.strftime(value, "%Y-%m-%d %H:%M")`; percent and quantity labels are hard-coded English.

## assets/js/app.js

- JS-updated labels/text: `Discount percentage`, `Discount amount`, `Enter 0 to remove this item discount.`, `The amount applies to this entire order line.`, `Remaining: ...`, `Change: ...`
- Selectors tied to labels: `Increase quantity`, `Decrease quantity`, `Requested quantity`, `Edit selected product`
- Amount sources: DOM datasets from POS LiveView: `data-sale-total`, `data-price`, `data-sub`, `data-tax`, `data-discount`, `data-discount-type`, `data-order-discount`, `data-delivery`; payment input values; discount input values.
- Formatting: `new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"})` in payment, discount, and cart amount hooks.
- Locale flags: `en-US` and `USD` are hard-coded; minus sign is hard-coded as `−`; decimal parsing uses `Number.parseFloat`/`Number(...)` from raw input, which assumes dot decimal input.

## assets/js/receipt_printer/formatter.js

- Receipt labels: `RNC`, `e-NCF`, `Fecha`, `Cliente`, `Documento`, `Vendedor`, `COPIA`, `FACTURA A CREDITO`, `DIARIO DE VENTAS`, `DESCRIPCION`, `ITBIS`, `VALOR`, `SKU`, `Subtotal`, `Impuesto`, `Descuento`, `Entrega`, `Total`, `Ahorro en compra`, `Articulos`, `Total pagado a la fecha`, `Saldo pendiente`, `Devuelta`, `Gracias por su compra`, `Recibo`, `CONSUMIDOR FINAL`, `PRODUCTO`
- Payment method labels: `Tarjeta de credito`, `Efectivo`
- Amount sources: sale-level `sale.sub`/`sale.subtotal`, `sale.tax_amount`/`sale.tax`, `sale.discount`, `sale.delivery_charge`/`sale.delivery`, `sale.amount`/`sale.total`, `sale.total_paid`, `sale.due_balance`, `sale.change_amount`; line-level `item.amount`/`item.price`/`product.price`, `item.total_amount`/`item.total`, `item.tax_amount`/`item.tax`, `item.sub`/`item.subtotal`, `item.discount`; payment `payment.amount`.
- Formatting: local `money(value)` uses `Number`, `Math.abs(...).toLocaleString("en-US", {minimumFractionDigits: 2, maximumFractionDigits: 2})`, then prepends hard-coded `$` and optional `-`.
- Locale flags: hard-coded `$`, `en-US` number/date formats, manual tax fallback `total - total / 1.18`, hard-coded column widths, uppercase receipt text via `.toUpperCase()`.

## assets/js/receipt_printer/transport.js

- Error messages: `WebUSB is not supported in this browser.`, `Selected USB device has no writable endpoint.`, `Printer is not connected.`

## assets/js/receipt_printer/service.js

- Error message: `No receipt printer is connected.`

## priv/static/assets/company-settings-live.js

- Upload/help messages: `Choose a valid image before saving.`, `Image must be 10 MB or smaller.`, `Resizing image…`, `Image conversion failed`, `... resized to ... px and ready as Base64.`, `Image could not be prepared: ...`, `Logo will be removed when you save.`, `Image is still being prepared. Please wait.`, `Choose a valid image or remove it before saving.`
- Locale flags: file size unit `MB`, image dimension text `px`, and English status sentence composition are hard-coded.

## priv/static/assets/login-live.js

- Error message: `session login failed` (developer-facing but thrown during a user-facing login flow).

## lib/tigoo_server_web/live/company_settings_live.ex

- Page title/flash/status: `Tigoo Company settings`, `Company settings access is required.`, `This item could not be found.`, `The selected store is unavailable.`, `Company settings could not be loaded.`
- Header/cards: `Company`, `Company settings`, `Current company`, `Price lists`, `Manage the labels used for product prices.`, `Add price list`, `No price lists yet.`, `Stores`, `Manage your company’s store locations.`, `Add store`, `No stores yet.`, `Sequence sets`, `Set the invoice sequences used for CF, VF, and DV sales.`, `Add sequence`, `No sequences configured. Add CF, VF, and DV to complete sales.`, `Providers`, `Manage the providers used for purchase orders.`, `Add provider`, `No providers yet.`
- Form labels/buttons: `Name`, `Code`, `Prefix`, `Digits`, `Increment`, `Next number`, `Price list label`, `Provider name`, `Store name`, `Company:`, `Current company`, `Slogan`, `Address`, `Store logo preview`, `Store logo`, `Drop an image here or choose a file (max 10 MB). It will be resized and stored as Base64.`, `Remove logo`, `Cancel`, `Save`, `Create`, `Edit`, `Delete`
- Confirm/errors: `Delete this price list?`, `Delete this sequence set?`, `Delete this ...?`, `Could not save price list.`, `Could not save store.`, `Could not save provider.`, `Could not save sequence set.`, `Could not delete price list.`, `Could not delete provider.`, `Could not delete sequence set.`
- Locale flags: sequence row description uses English sentence `increments by`; company RNC label is hard-coded.

## lib/tigoo_server_web/live/customer_live.ex

- Page title/status/errors: `Tigoo Customers`, `Loading customers…`, `Customer access is required.`, `The selected store is unavailable.`, `Could not create customer. Check the data and try again.`, `No customers found.`, `Could not load customers. Check the server connection.`, `Customer details could not be loaded: ...`
- Amount path: delegates rendering to `CustomerComponents`.

## lib/tigoo_server_web/components/customer_components.ex

- Customer list: `Customers`, `Customer list`, `Create customer`, `Back`, `Search customers`, `Search customers by name or phone`, `Customer accounts and purchase activity.`, `Name`, `Document ID`, `Phone`, `Email`, `Wholesale`, `Pending balance`, `Last purchase`, `View`, `Yes`, `No`
- Customer detail: `Customer detail`, `Back to customers`, `Loading customer details`, `Customer account`, `Customer`, `No document ID`, `No phone`, `No address`, `No email`, `Retail`, `Created`, `Pending balance`, `Total invoiced`, `Total paid`, `Outstanding balance`, `Purchases`, `Last purchase`, `Purchase history`, `Invoice`, `Date`, `Total`, `Paid`, `Balance`, `Status`, `Sales Person`, `Store`, `Action`, `No purchases found for this customer.`
- Dialog/form: `Create customer`, `Add a customer, then use them on this sale.`, `Address`, `Is wholesaler`, `Cancel`, `Save customer`
- Amount sources: list `@customer.pending_balance`; summary `summary.pending_balance`, `summary.total_invoiced`, `summary.total_paid`; purchases `purchase.amount`, `purchase.total_paid`, `purchase.due_balance`.
- Formatting: private `money/1` returns `"$" <> :erlang.float_to_binary(float(value), decimals: 2)`.
- Locale flags: hard-coded `$`, dot decimal, no thousands grouping; dates use `%-m/%-d/%Y` and `%Y-%m-%d %H:%M`.

## lib/tigoo_server_web/live/invoice_report_live.ex

- Page/filters/table text: invoice report title/header text, invoice search placeholder, date range controls, KPI labels for invoice statuses, table headers `Invoice`, `Customer`, `Date`, `Due Date`, `Status`, `Total`, `Balance`, `Sales Person`, `Actions`, `Cancel`
- Row/detail labels: `Walk-in customer`, `Sales`, `Due date:`, `Print Copy`, `Payments`, `Payment`, `User`, `Method`, `Amount`, `No payments recorded.`, `Credit Card`, `Cash`, `Complete`, `Partial`, `Print payment`, `Line items`, `Product`, `Quantity`, `Unit price`, `Discount`, `Subtotal`, `Tax (18%)`, `Delivery`, `Payment amount`, `Apply`, `Pay off`
- Status labels/functions include invoice statuses such as `Open`, `Closed`, `Cancelled` (via status label helper).
- Amount sources: KPI summary `summary["#{name}_total"]`; invoice row `invoice["amount"]`, `invoice["due_balance"]`; payments `payment.amount`; line item `line.amount`, `line.discount`, `line.total_amount`; detail totals `detail.discount`, `detail.sub`, `detail.tax_amount`, `detail.delivery_charge`, `detail.amount`, `detail.due_balance`.
- Formatting: private `money/1` converts Decimal to float and returns `"$#{float_to_binary(..., decimals: 2)}"`.
- Locale flags: hard-coded `$`, dot decimal, no thousands grouping; `Tax (18%)`; date range composition and date/time helper formats are hard-coded; discount display emits `%` for percentage discounts.

## lib/tigoo_server_web/live/inventory_live.ex

- Page/status text: `Operations`, `Inventory`, `Search product`, `Archived`, `Create product`, inventory status messages
- KPI labels/details: `Inventory and operations KPIs`, `Inventory valuation`, `Company total`, `Store`, `Negative stock`, `Uncosted inventory`, `Stockout`, `Net sales`, `Sales mix`, `Average order`, `Best products`, `Discount rate`, `Payment mix`, `Retention`, `Order flow`, `No activity`, `Recorded payments`, `Show fewer KPIs`, `Show more KPIs`
- Inventory table: `Inventory by store.`, `Product`, `Status`, `SKU`, `Cost`, `Price`, `Total quantity`, `Current quantity`, `Active`, `Archive it`, status tooltip `Product status: ...`
- Trace/context labels: `To:`, `From:`, `source/destination/reference ... #...`
- Amount sources: `summary.company_inventory_valuation`, `store.inventory_valuation`, `summary.negative_stock_value`, `summary.net_sales`, `sales_mix[].net_sales`, `summary.average_order_value`, `best_products[].net_revenue`, `summary.net_discount`, `payment_method_mix[].amount`, `summary.average_customer_value`, `entry.product_cost`, `entry.product_price`.
- Formatting: private `money/1` returns `"$" <> :erlang.float_to_binary(decimal(value), decimals: 2)`; `percent/1` multiplies by 100 and appends `%`; unit counts use `Float.round(..., 1/0)` and English `units`, `SKUs`, `sales`, `customers`, `purchase orders`, `closed`, `discount`.
- Locale flags: hard-coded `$`, dot decimal, `%`, English plural nouns and metric sentence composition.

## lib/tigoo_server_web/live/purchase_orders_live.ex

- List/table text: `Operations`, purchase order title/header text, `Purchase orders`, `Purchase orders for the current store.`, `Order ID`, `Source`, `Destination store`, `Order cost`, `Cost difference`, `Status`, `Last updated`, `Created by`, `Action`, `Closed`, `Open`, `Observed quantities differ from requested quantities`, `View`
- Detail/form text: `Purchase order`, `Move products`, `Back to orders`, `Order #...`, `External source`, `Created by`, `Previous`, `Next`, `Start Counting`, `Process Order`, `Products in this purchase order.`, `Product`, `SKU`, `Current quantity`, `Requested`, `Observed`, `Item cost`, `Cost difference`, `Create purchase order`, `Move products from an origin store to a destination store.`, `Add products and confirm the requested quantities.`, `Origin store`, `Source / provider`, `Select a source`
- Amount sources: `order_cost(order)`, `order_difference(order)`, `line_cost(line, order)`, `difference(line, order)`.
- Formatting: private `money/1` returns `"$" <> :erlang.float_to_binary(decimal(value), decimals: 2)`.
- Locale flags: hard-coded `$`, dot decimal, no thousands grouping; status names come partly from DB and partly hard-coded.

## lib/tigoo_server_web/components/pos_user_components.ex

- Users list/detail/form text: `Users`, `Search users`, `Username`, `User type`, `Employee`, `Stores`, `Permissions`, `Active user`
- Additional labels/buttons/statuses should be translated wherever the component renders create/edit/view user forms and permission lists.

## lib/tigoo_server_web/live/pos_user_live.ex

- Page title/status/errors: `Tigoo Users`, `Loading users...`, `Sign in is required to manage users.`, `The selected store is unavailable.`, `User settings permission is required.`
- Save/delete/status messages and mode labels in event handlers should be included with the component text above.

## lib/tigoo_server_web/live/user_live.ex

- Flash/errors: `... and their company workspace have been created.`, `The tenant workspace could not be created. Please try again.`, `... has been confirmed.`, `The user could not be confirmed. Please try again.`, `The user could not be found.`
- Admin list: `Administration`, `People`, `Toggle color theme`, `Directory`, `Review confirmation status and workspace access.`, `Directory summary`, `Total accounts`, `All user accounts`, `Awaiting confirmation`, `Require review`, `User directory`, `Manage account confirmation and workspaces.`, `Search users`, `Search people`, `Retaily user accounts and their confirmation state.`, `User`, `Workspace`, `Status`, `Actions`, `No accounts yet.`, `Create a user to start the directory.`, `Create user`, `Confirmed`, `Pending`
- Create user: `Create user`, `Add a person`, `Create an account and its initial company workspace.`, `Person`, `The account owner for this workspace.`, `Full name`, `Email address`, `Temporary password`, `At least 6 characters.`, `Company workspace`, `Company name`, `RNC`, `Workspace ID`, `Lowercase letters, numbers, and underscores only.`, `Cancel`, `Save user`

## lib/tigoo_server_web/components/dashboard_components.ex

- Sidebar labels: `Primary navigation`, `tigoo dashboard`, `Collapse navigation`, `Dashboard navigation`, `Dashboard`, `Install Addon`, `Workspace management`

## lib/tigoo_server_web/controllers/dashboard_html/index.html.heex

- Dashboard copy: `Overview`, `Dashboard`, `Toggle color theme`, `Welcome back, ...`, `Manage your account confirmation and workspace setup.`, `Account summary`, `Account status`, `Workspace`, `Confirmation pending`, `No action needed`, `Create workspace`, `Set up the company workspace for this account.`, `Company name`, `Workspace ID`, `RNC (optional)`, `Workspace details`, `Your active company workspace.`, `Company`

## lib/tigoo_server_web/controllers/admin_session_html/new.html.heex

- Admin login copy: `Administration`, `Admin sign in`, `Sign in to access the administration area.`, `Username`, `Password`, `Login`

## lib/tigoo_server_web/controllers/google_auth_controller.ex

- OAuth result HTML: page titles `Signed in`, `Sign-in failed`; body text `You’re signed in to tigoo`, `You can close this page and return to the app.`, `Sign-in couldn’t be completed`, `You can close this page and try again from tigoo.`

## lib/tigoo_server_web/controllers/addon_html/install.html.heex

- Addon catalog copy: `Extensions`, `Apps`, `Available apps`, `Extend your workspace with server-managed business tools.`

## lib/tigoo_server_web/controllers/landing_html/index.html.heex

- Spanish landing navigation/CTA/legal text: `Inicio`, `Solución`, `Preguntas`, `Contacto`, `Iniciar sesión`, `Abrir menú de cuenta`, `Visita tu perfil`, `Abrir menú de navegación`, `Factura electrónica DGII`, `Controla todo en un solo lugar.`, `conecta ventas, inventario y clientes`, `Factura con la DGII. Vende desde donde estés`, `Todo lo que necesitas para vender`, `Fácil de usar`, `Empieza a vender sin una curva de aprendizaje complicada.`, `Todo conectado`, `Ventas, productos, clientes e inventario trabajan juntos.`, `Acceso donde estés`, `Mantén visibilidad de tu negocio desde tus dispositivos.`, `Tu negocio va contigo`, `Una solución que crece contigo`, `Ventas e inventario`, `Vende rápido y controla cada producto.`, `Preparado para crecer`, `Preguntas sobre tigoo`, `Conoce tigoo`, `Vende, controla y factura. Conoce todo lo que tigoo puede hacer.`, `Visitar tigoo`, `Vista de tigoo`, `Tu negocio merece una solución más simple.`, `tigoo © 2026 · Ventas, inventario y facturación para avanzar.`, `Información legal`, `Política de privacidad`, `Términos de servicio`, `Copiar la dirección web de tigoo`
- Also includes English placeholder/portfolio-like words around lines 391-470: `I'm`, `UI/UX`, `designer`, `Web Developer`, `focused`, `creating`, `experiences`, `functional`, `beautiful.`, `Figma`, `Framer`, `ChatGPT`, `Gemini`, `Next.js`, `Tailwind CSS.`
- Locale flags: Spanish copy, English fragments, and hard-coded copyright year `2026`.

## lib/tigoo_server_web/controllers/landing_html/privacy_policy.html.heex

- Legal/nav/footer text: `tigoo: Inicio`, `Inicio`, `Términos de servicio`, `Legal`, `Política de privacidad`, `Última actualización: 3 de septiembre de 2026`, section headings and full policy paragraphs, `tigoo © 2026`, `Información legal`
- Locale flags: hard-coded Spanish date and copyright year.

## lib/tigoo_server_web/controllers/landing_html/terms_of_service.html.heex

- Legal/nav/footer text: `tigoo: Inicio`, `Inicio`, `Privacidad`, `Legal`, `Términos de servicio`, `Última actualización: 3 de septiembre de 2026`, section headings and full terms paragraphs, `tigoo © 2026`, `Información legal`, `Política de privacidad`
- Locale flags: hard-coded Spanish date and copyright year.

## lib/tigoo_server_web/components/layouts.ex

- Phoenix scaffold/default text still present: `Content`, `Website`, `GitHub`, `Get Started`, `Welcome Back!`, `Send!`, `Home`, sample table titles such as `Title`, `Views`.
- These may not be active in the POS UI, but should be removed or translated if exposed.

## lib/tigoo_server_web/components/core_components.ex

- Component examples/docs contain sample strings such as `Welcome Back!`, `Send!`, `Home`, `Title`, `Views`.
- Runtime flash/input/table component text should be audited if examples are rendered; otherwise mostly developer examples.

## Global amount/i18n risks

- Currency formatting is duplicated in at least six places: `pos_live.ex`, `invoice_report_live.ex`, `inventory_live.ex`, `purchase_orders_live.ex`, `customer_components.ex`, `assets/js/app.js`, and `assets/js/receipt_printer/formatter.js`.
- Hard-coded currency symbols: `$` in Elixir money helpers, JS `Intl.NumberFormat(... currency: "USD")`, receipt formatter, and the POS discount amount toggle.
- Hard-coded separators/formats: Elixir helpers use dot decimal and sometimes comma thousands; JS uses `en-US`; several Elixir helpers have no thousands grouping.
- Hard-coded tax labels/rates: `Tax (18%)`, receipt `ITBIS`, and receipt fallback `1.18`.
- Hard-coded date formats: `%-m/%-d/%Y`, `%Y-%m-%d %H:%M`, JS `toLocaleString("en-US")`, `toLocaleDateString("en-US")`, and Spanish legal date literals.
- User-entered decimal parsing uses `Float.parse`, `Number.parseFloat`, and number inputs with `step="0.01"`; future locale support should decide how localized decimal input is handled.
