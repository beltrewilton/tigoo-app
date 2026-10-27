defmodule TigooServerWeb.Router do
  use TigooServerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TigooServerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug TigooServerWeb.Plugs.ResolveTenant, required: false
    plug TigooServerWeb.Plugs.FetchCurrentScope
  end

  pipeline :tenant_browser do
    plug TigooServerWeb.Plugs.ResolveTenant
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :put_desktop_cors_headers
  end

  pipeline :fe_api do
    plug :accepts, ["xml", "json"]
  end

  pipeline :tenant_login_api do
    plug :accepts, ["json"]
    plug :put_desktop_cors_headers
    plug TigooServerWeb.Plugs.ResolveTenant, base: :not_found
  end

  # The LiveView ESM client is a public, read-only asset. It must not pass
  # through the browser CSRF plug because that plug protects JavaScript
  # responses against cross-origin script embedding.
  pipeline :liveview_asset do
    plug :accepts, ["js", "css"]
  end

  pipeline :admin do
    plug TigooServerWeb.Plugs.RequireAdminSession
  end

  pipeline :tenant_api do
    plug :accepts, ["json"]
    plug :put_desktop_cors_headers
    plug TigooServerWeb.Plugs.ResolveTenant, base: :not_found
    plug TigooServerWeb.Plugs.FetchCurrentScope
    plug TigooServerWeb.Plugs.PutTenantFromScope
    plug TigooServerWeb.Plugs.RequireTenant
    plug TigooServerWeb.Plugs.RequirePermission
  end

  scope "/fe/autenticacion/api", TigooServerWeb do
    pipe_through :fe_api

    get "/semilla", FeAuthenticationController, :semilla
    post "/validacioncertificado", FeAuthenticationController, :validacioncertificado
  end

  scope "/fe/recepcion/api", TigooServerWeb do
    pipe_through :fe_api

    post "/ecf", FeReceptionController, :create
  end

  scope "/", TigooServerWeb do
    pipe_through :browser

    get "/", LandingController, :index
    get "/privacy-policy", LandingController, :privacy_policy
    get "/terms-of-service", LandingController, :terms_of_service
    get "/google_auth_url", GoogleAuthController, :redirect_to
    get "/auth/google/tauri", GoogleAuthController, :tauri_redirect_to
    get "/auth/google/callback", GoogleAuthController, :callback
    get "/google_helper", GoogleAuthController, :helper
    post "/logout", GoogleAuthController, :logout
    get "/pos/dashboard", DashboardController, :index
    post "/pos/dashboard/tenant", DashboardController, :create
  end

  scope "/", TigooServerWeb do
    pipe_through [:browser, :tenant_browser]

    post "/pos/dashboard/logo", DashboardController, :update_logo
    live "/pos/login", LoginLive, :index
    post "/pos/login/session", BrowserLoginController, :create
    delete "/pos/logout", BrowserLoginController, :delete
    live "/pos", PosLive, :index
    live "/pos/reconciliation", CashReconciliationLive, :index
    live "/pos/customers", CustomerLive, :index
    live "/pos/invoices", InvoiceReportLive, :index
    live "/pos/ecf-tests", EcfTestLive, :index
    live "/pos/ecf-tests/:id/xml", EcfTestXmlLive, :index
    get "/pos/ecf-tests/:id/dgii", EcfTestXmlController, :verify
    get "/pos/ecf-tests/:id/xml/download", EcfTestXmlController, :download
    live "/pos/inventory", InventoryLive, :index
    live "/pos/orders", PurchaseOrdersLive, :index
    get "/pos/addons", AddonController, :index
    live "/pos/company-settings", CompanySettingsLive, :index
    live "/pos/sequences", SequencesLive, :index
    live "/pos/users", PosUserLive, :index
  end

  scope "/", TigooServerWeb do
    pipe_through :liveview_asset

    get "/liveview-client.js", LiveViewAssetController, :show
    get "/pos-client.css", LiveViewAssetController, :pos_css
    get "/login-client.css", LiveViewAssetController, :login_css
  end

  scope "/pos/addons", TigooServerWeb do
    pipe_through [:browser, :tenant_browser]

    get "/install", AddonController, :install_index
    post "/install", AddonController, :install
    get "/:identifier", AddonController, :show
  end

  scope "/addons", TigooServerWeb do
    pipe_through [:browser, :tenant_browser]

    post "/:identifier/uninstall", AddonController, :uninstall
    get "/:identifier", AddonController, :legacy_show
  end

  scope "/admin", TigooServerWeb do
    pipe_through :browser

    get "/login", AdminSessionController, :new
    post "/login", AdminSessionController, :create
    post "/logout", AdminSessionController, :delete
  end

  scope "/admin", TigooServerWeb do
    pipe_through [:browser, :admin]

    live "/", UserLive, :index
    live "/users", UserLive, :index
    live "/users/new", UserLive, :new
  end

  scope "/api", TigooServerWeb do
    pipe_through :tenant_login_api

    post "/login", AuthController, :login
  end

  scope "/api", TigooServerWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/auth/tauri/attempts", TauriAuthController, :create_attempt
    post "/auth/tauri/exchange", TauriAuthController, :exchange
    options "/*path", HealthController, :show
  end

  scope "/api", TigooServerWeb do
    pipe_through :tenant_api

    get "/users", UserController, :index
    get "/users/options", UserController, :options
    get "/users/:id", UserController, :show
    post "/users", UserController, :create
    patch "/users/:id", UserController, :update
    delete "/users/:id", UserController, :delete

    get "/products", ProductController, :index
    get "/products/:id", ProductCreateController, :show
    post "/products", ProductCreateController, :create
    patch "/products/:id", ProductCreateController, :update
    post "/products/:id/prices", ProductCreateController, :set_prices
    get "/pricing-lists", PricingController, :index
    get "/stores", StoreController, :index
    get "/company-settings", CompanySettingsController, :index
    post "/company-settings/price-lists", CompanySettingsController, :create_price_list
    patch "/company-settings/price-lists/:id", CompanySettingsController, :update_price_list
    delete "/company-settings/price-lists/:id", CompanySettingsController, :delete_price_list
    post "/company-settings/stores", CompanySettingsController, :create_store
    patch "/company-settings/stores/:id", CompanySettingsController, :update_store
    delete "/company-settings/stores/:id", CompanySettingsController, :delete_store
    post "/company-settings/sequences", CompanySettingsController, :create_sequence_set
    patch "/company-settings/sequences/:id", CompanySettingsController, :update_sequence_set
    delete "/company-settings/sequences/:id", CompanySettingsController, :delete_sequence_set
    post "/company-settings/providers", CompanySettingsController, :create_provider
    patch "/company-settings/providers/:id", CompanySettingsController, :update_provider
    delete "/company-settings/providers/:id", CompanySettingsController, :delete_provider
    get "/inventory", InventoryController, :index
    get "/inventory/:product_id/traces", InventoryController, :traces
    get "/inventory/summary", InventoryController, :summary
    post "/inventory/adjustments", InventoryController, :adjust
    post "/inventory/moves", InventoryController, :move
    post "/product-orders", ProductOrderController, :create
    get "/product-orders", ProductOrderController, :index
    get "/purchase-sources", PurchaseSourceController, :index
    post "/product-orders/:id/receive", ProductOrderController, :receive
    get "/customers", CustomerController, :index
    get "/customers/:id", CustomerController, :show
    get "/customers/:id/purchases", CustomerController, :purchases
    post "/customers", CustomerController, :create
    patch "/customers/:id", CustomerController, :update
    get "/sales/report", SaleController, :report
    get "/sales", SaleController, :index
    get "/sales/ecf-tests/:id", SaleController, :ecf_test_status
    get "/sales/:id", SaleController, :show
    post "/sales", SaleController, :create
    post "/sales/:id/payments", SaleController, :add_payment
    post "/sales/:id/cancel", SaleController, :cancel
  end

  # The Tauri webview is served from its own origin. Tenant-owned routes use
  # bearer authentication in the :tenant_api pipeline.
  defp put_desktop_cors_headers(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_header("access-control-allow-origin", "*")
    |> Plug.Conn.put_resp_header("access-control-allow-headers", "authorization, content-type")
    |> Plug.Conn.put_resp_header(
      "access-control-allow-methods",
      "GET, POST, PUT, PATCH, DELETE, OPTIONS"
    )
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:tigoo_server, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TigooServerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/", TigooServerWeb do
    pipe_through :browser

    match :*, "/*path", LandingController, :not_found
  end
end
