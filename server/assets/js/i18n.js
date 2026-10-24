const LANGUAGE_KEY = "pos-display-language"

export const LANGUAGES = {
  en: {label: "English", locale: "en-US", currency: "USD"},
  es: {label: "Español", locale: "es-DO", currency: "DOP"},
  pt: {label: "Português", locale: "pt-BR", currency: "BRL"}
}

const en = {
  sequences: {"title": "Sequences", "standard": "Sales sequences", "rotation": "Monthly rotating sequences", "standardCopy": "Configure invoice numbers for CF, VF and DV sales.", "rotationCopy": "Configure a monthly window with cyclic number reuse.", "empty": "No sequences configured.", "base": "Current base", "windowSize": "Window size", "allowedSteps": "Allowed steps", "period": "Month", "step": "Step", "lastNumber": "Last number", "estimated": "Estimated monthly amount", "allowed": "Allowed monthly amount", "average": "Average amount", "rotationHelp": "Counts are calculated automatically. Active-month configuration and an initialized base cannot be edited.", "loadFailed": "Sequences could not be loaded.", "saveFailed": "Could not save sequence.", "deleteFailed": "Could not delete sequence."},
  layout: {
    nav: {
      primary: "Primary navigation",
      pos: "POS",
      customers: "Customers",
      invoices: "Invoice report",
      inventory: "Inventory",
      orders: "Purchase orders",
      companySettings: "Company settings",
      users: "Users",
      expand: "Expand navigation",
      collapse: "Collapse navigation"
    },
    theme: {
      choose: "Choose theme",
      label: "Theme",
      defaultLight: "Default Light",
      natureLight: "Nature Light",
      natureDark: "Nature Dark",
      caffeineLight: "Caffeine Light",
      caffeineDark: "Caffeine Dark",
      boldTechLight: "Bold Tech Light",
      boldTechDark: "Bold Tech Dark",
      doom64Light: "Doom 64 Light",
      doom64Dark: "Doom 64 Dark"
    },
    store: {choose: "Choose active store", active: "Active store"},
    user: {menu: "User menu", openMenuFor: "Open menu for {name}", logout: "Logout"},
    status: {
      system: "System status",
      language: "Change display language",
      printerDisconnected: "Printer disconnected",
      printerConnecting: "Printer connecting",
      printerConnected: "Printer connected",
      printerError: "Printer error",
      networkConnected: "Network connected",
      networkDisconnected: "Network disconnected",
      loadingInvoiceDetails: "Loading invoice details",
      loadingScreenContent: "Loading screen content"
    }
  },
  common: {
    action: "Action",
    actions: "Actions",
    add: "Add",
    apply: "Apply",
    back: "Back",
    balance: "Balance",
    cancel: "Cancel",
    cash: "Cash",
    choose: "Choose",
    clear: "Clear",
    closed: "Closed",
    code: "Code",
    complete: "Complete",
    continue: "Continue",
    create: "Create",
    date: "Date",
    delete: "Delete",
    discount: "Discount",
    documentId: "Document ID",
    edit: "Edit",
    email: "Email",
    item: "Item",
    items: "Items",
    loading: "Loading...",
    name: "Name",
    no: "No",
    open: "Open",
    payment: "Payment",
    phone: "Phone",
    price: "Price",
    product: "Product",
    quantity: "Quantity",
    save: "Save",
    status: "Status",
    store: "Store",
    subtotal: "Subtotal",
    tax: "Tax",
    tax18: "Tax (18%)",
    total: "Total",
    user: "User",
    view: "View",
    yes: "Yes"
  },
  pos: {
    pageTitle: "Tigoo Sign in",
    errors: {
      noStore: "No store is available for this account.",
      storesUnavailable: "Stores could not be loaded.",
      invalidLogin: "The username/email or password is incorrect.",
      selectStore: "Select a store to continue.",
      googleUnavailable: "Google sign-in is available in the desktop or mobile app.",
      unableSignIn: "Unable to sign in.",
      productsUnavailable: "Products could not be loaded."
    },
    login: {
      signIn: "Sign in",
      copy: "Use your username or email and password to continue.",
      usernameOrEmail: "Username or email",
      password: "Password",
      store: "Store",
      selectStore: "Select a store",
      continueWithGoogle: "Continue with Google"
    },
    catalog: {
      pointOfSale: "Point of Sale",
      searchProducts: "Search products or scan a barcode",
      focusSearch: "Focus product search",
      catalog: "Catalog",
      products: "Products",
      loadingProducts: "Loading products…",
      noMatchingProducts: "No matching products.",
      scrollForMore: "Scroll for more products",
      productsLoaded: "products loaded",
      viewSale: "View sale",
      addProduct: "Add {name}",
      unnamedProduct: "Unnamed product",
      sku: "SKU",
      tapToAdd: "Tap to add",
      stock: "Stock"
    },
    customers: {
      customers: "Customers",
      customerList: "Customer list",
      createCustomer: "Create customer",
      editCustomer: "Edit customer",
      createCustomerTypo: "Crear client",
      searchCustomers: "Search customers",
      searchCustomersPlaceholder: "Search customers by name or phone",
      noCustomersFound: "No customers found.",
      accountsCaption: "Customer accounts and purchase activity.",
      customerAction: "Customer action",
      chooseCustomer: "Choose: customer",
      detail: "Customer detail",
      backToCustomers: "Back to customers",
      loadingDetails: "Loading customer details",
      account: "Customer account",
      noDocumentId: "No document ID",
      noPhone: "No phone",
      noAddress: "No address",
      noEmail: "No email",
      retail: "Retail",
      wholesale: "Wholesale",
      created: "Created",
      pendingBalance: "Pending balance",
      totalInvoiced: "Total invoiced",
      totalPaid: "Total paid",
      outstandingBalance: "Outstanding balance",
      purchases: "Purchases",
      lastPurchase: "Last purchase",
      purchaseHistory: "Purchase history",
      invoice: "Invoice",
      salesPerson: "Sales Person",
      noPurchases: "No purchases found for this customer.",
      addDialogCopy: "Add a customer, then use them on this sale.",
      editDialogCopy: "Update this customer's account and contact details.",
      address: "Address",
      isWholesaler: "Is wholesaler",
      saveCustomer: "Save customer"
    },
    checkout: {
      checkout: "Checkout",
      customer: "Customer",
      paymentCompletion: "Payment & completion",
      backToSale: "Back to sale",
      progress: "Checkout progress",
      stepCustomer: "1. Customer",
      stepPayment: "2. Payment",
      pickCustomer: "Pick a customer…",
      pickCustomerSpaced: "Pick a customer …",
      sequenceType: "Sequence type",
      consumerFinal: "Consumer final",
      directSale: "Direct sale",
      fiscalVoucher: "Fiscal voucher",
      delivery: "Delivery",
      freeAmount: "Free amount",
      deliveryFreeAmount: "Delivery free amount",
      selectDeliveryFreeAmount: "Select delivery free amount",
      payOnCredit: "Pay on Credit",
      dueDate: "Due date",
      payments: "Payments",
      creditCard: "Credit Card",
      removePayment: "Remove payment",
      addPayment: "Add payment",
      remaining: "Remaining:",
      change: "Change:",
      memoOptional: "Memo (optional)",
      memoHelp: "Up to 1000 characters.",
      paymentMethod: "Payment method"
    },
    cart: {
      currentSale: "Current sale",
      openCurrentSale: "Open current sale",
      viewCustomerPurchases: "View customer purchases",
      clearCustomer: "Clear customer",
      closeSale: "Close sale",
      empty: "Your order is empty. Select a product to begin.",
      discountItem: "Apply a discount to this item",
      off: "off",
      sub: "Sub",
      each: "each",
      removeProduct: "Remove {name}",
      decreaseQuantity: "Decrease quantity",
      itemCount: "Item count",
      increaseQuantity: "Increase quantity",
      discountSale: "Apply a discount to this sale",
      applyOrderDiscount: "Apply order discount. Press Enter.",
      clearTitle: "Clear this order?",
      clearDescription: "All items and line discounts will be removed.",
      clearOrder: "Clear order"
    },
    discount: {
      lineItem: "Line item discount",
      order: "Order discount",
      applyLine: "Apply a discount",
      applyOrder: "Apply an order discount",
      type: "Discount type",
      percentage: "Discount percentage",
      amount: "Discount amount",
      finalPrice: "Price after discount",
      percentHelp: "Enter 0 to remove this item discount.",
      amountHelp: "The amount applies to this entire order line.",
      orderAmountHelp: "The amount applies to this order before delivery.",
      finalPriceLineHelp: "Enter the final price for this entire order line.",
      finalPriceOrderHelp: "Enter the final price for this order before delivery.",
      amountLabel: "Amount",
      afterDiscount: "After discount",
      applyDiscount: "Apply discount",
      orderHelp: "Choose a percentage or amount for this order."
    },
    purchases: {
      recent: "recent purchases",
      latest10: "The 10 most recent purchases, newest first.",
      noPurchasesFound: "No purchases found.",
      caption: "Customer purchase history. Expand an item count to view the sold items.",
      productNumber: "Product #{id}",
      saleNumber: "sale {id}"
    },
    print: {
      completed: "Sale completed",
      prompt: "Would you like to print the receipt?",
      printReceipt: "Print receipt",
      skip: "Skip"
    }
  },
  invoice: {
    title: "Invoice report",
    sales: "Sales",
    search: "Search invoices by customer",
    searchPlaceholder: "Search by customer name",
    summary: "Invoice status summary",
    selectedStoreCaption: "Invoices for the selected store.",
    dueDateHeader: "Due Date",
    walkIn: "Walk-in customer",
    dueDate: "Due date:",
    printCopy: "Print Copy",
    payments: "Payments",
    method: "Method",
    amount: "Amount",
    noPayments: "No payments recorded.",
    partial: "Partial",
    printPayment: "Print payment",
    lineItems: "Line items",
    unitPrice: "Unit price",
    price: "Price",
    paymentAmount: "Payment amount",
    paid: "Paid",
    payOff: "Pay off",
    anyDate: "Any date",
    selectDateRange: "Select date range",
    chooseEndDate: "Choose an end date.",
    chooseStartEndDate: "Choose a start date, then an end date.",
    previousMonth: "Previous month",
    nextMonth: "Next month",
    applyRange: "Apply range",
    cancelInvoiceTitle: "Cancel invoice?",
    cancelInvoiceCopy: "This restores the sold inventory. This action cannot be undone from the report.",
    selectedInvoice: "Selected invoice",
    keepInvoice: "Keep invoice",
    cancelInvoice: "Cancel invoice",
    printPaymentTitle: "Print Payment",
    printPaymentPrompt: "Would you like to print this payment receipt?",
    printCopyTitle: "Print copy",
    noReturnToPos: "No, return to POS",
    cancelled: "Cancelled",
    confirmed: "Confirmed",
    pending: "Pending"
  },
  inventory: {
    operations: "Operations",
    inventory: "Inventory",
    searchProduct: "Search product",
    archived: "Archived",
    createProduct: "Create product",
    kpis: "Inventory and operations KPIs",
    valuation: "Inventory valuation",
    companyTotal: "Company total",
    negativeStock: "Negative stock",
    uncostedInventory: "Uncosted inventory",
    stockout: "Stockout",
    netSales: "Net sales",
    salesMix: "Sales mix",
    averageOrder: "Average order",
    bestProducts: "Best products",
    discountRate: "Discount rate",
    paymentMix: "Payment mix",
    retention: "Retention",
    orderFlow: "Order flow",
    noActivity: "No activity",
    recordedPayments: "Recorded payments",
    showFewerKpis: "Show fewer KPIs",
    showMoreKpis: "Show more KPIs",
    byStore: "Inventory by store.",
    cost: "Cost",
    totalQuantity: "Total quantity",
    currentQuantity: "Current quantity",
    active: "Active",
    archiveIt: "Archive it",
    productStatus: "Product status: {status}",
    update: "Update",
    previousQuantity: "Previous quantity",
    lastUpdated: "Last updated",
    updatedBy: "Updated by",
    noTraceHistory: "No trace history yet.",
    change: "Change",
    previousCurrent: "Previous → Current",
    context: "Context",
    to: "To:",
    from: "From:"
  },
  reconciliation: {
    title: "Cash Reconciliation",
    printReport: "Print report",
    printTitle: "Print reconciliation",
    printDescription: "Print the cash reconciliation receipt.",
    registerInputs: "Register inputs",
    cashier: "Cashier",
    openingCash: "Opening cash",
    salesCount: "Sales count",
    cashPayments: "Cash payments",
    cardPayments: "Credit/debit card payments",
    totalSales: "Total sales",
    expectedCashDrawer: "Expected cash drawer",
    reportPreview: "Report preview",
    receipt: "Receipt"
  },
  orders: {
    purchaseOrders: "Purchase orders",
    currentStore: "Purchase orders for the current store.",
    orderId: "Order ID",
    source: "Source",
    destinationStore: "Destination store",
    orderCost: "Order cost",
    costDifference: "Cost difference",
    lastUpdated: "Last updated",
    createdBy: "Created by",
    observedDiffers: "Observed quantities differ from requested quantities",
    purchaseOrder: "Purchase order",
    moveProducts: "Move products",
    backToOrders: "Back to orders",
    orderNumber: "Order #{id}",
    externalSource: "External source",
    previous: "Previous",
    next: "Next",
    startCounting: "Start Counting",
    processOrder: "Process Order",
    productsInOrder: "Products in this purchase order.",
    requested: "Requested",
    observed: "Observed",
    itemCost: "Item cost",
    createPurchaseOrder: "Create purchase order",
    moveProductsCopy: "Move products from an origin store to a destination store.",
    addProductsCopy: "Add products and confirm the requested quantities.",
    originStore: "Origin store",
    sourceProvider: "Source / provider",
    selectSource: "Select a source"
  },
  company: {
    title: "Company settings",
    accessRequired: "Company settings access is required.",
    notFound: "This item could not be found.",
    storeUnavailable: "The selected store is unavailable.",
    loadFailed: "Company settings could not be loaded.",
    company: "Company",
    currentCompany: "Current company",
    priceLists: "Price lists",
    priceListsCopy: "Manage the labels used for product prices.",
    addPriceList: "Add price list",
    noPriceLists: "No price lists yet.",
    stores: "Stores",
    storesCopy: "Manage your company’s store locations.",
    addStore: "Add store",
    noStores: "No stores yet.",
    sequenceSets: "Sequence sets",
    sequenceCopy: "Set the invoice sequences used for CF, VF, and DV sales.",
    addSequence: "Add sequence",
    noSequences: "No sequences configured. Add CF, VF, and DV to complete sales.",
    providers: "Providers",
    providersCopy: "Manage the providers used for purchase orders.",
    addProvider: "Add provider",
    noProviders: "No providers yet.",
    prefix: "Prefix",
    digits: "Digits",
    increment: "Increment",
    nextNumber: "Next number",
    priceListLabel: "Price list label",
    providerName: "Provider name",
    storeName: "Store name",
    slogan: "Slogan",
    address: "Address",
    storeLogoPreview: "Store logo preview",
    storeLogo: "Store logo",
    uploadHelp: "Drop an image here or choose a file (max 10 MB). It will be resized and stored as Base64.",
    removeLogo: "Remove logo"
  },
  users: {
    users: "Users",
    searchUsers: "Search users",
    username: "Username",
    userType: "User type",
    employee: "Employee",
    stores: "Stores",
    permissions: "Permissions",
    activeUser: "Active user",
    active: "Active",
    inactive: "Inactive",
    createUser: "Create user",
    deactivate: "Deactivate",
    details: "Details",
    firstName: "First name",
    lastName: "Last name",
    newPassword: "New password (leave blank to keep current)",
    assignedStores: "Assigned stores",
    noPermissions: "No permissions",
    noStores: "No stores",
    loading: "Loading users...",
    signinRequired: "Sign in is required to manage users.",
    permissionRequired: "User settings permission is required."
  },
  dashboard: {
    overview: "Overview",
    dashboard: "Dashboard",
    toggleTheme: "Toggle color theme",
    welcomeBack: "Welcome back, {name}",
    manageAccount: "Manage your account confirmation and workspace setup.",
    accountSummary: "Account summary",
    accountStatus: "Account status",
    workspace: "Workspace",
    confirmationPending: "Confirmation pending",
    noActionNeeded: "No action needed",
    awaitingConfirmation: "Awaiting confirmation",
    ready: "Ready",
    pendingReview: "Pending review",
    notCreated: "Not created",
    createAfterConfirmation: "Create it after confirmation",
    awaitingAdmin: "Your account is awaiting confirmation from an administrator.",
    createWhenConfirmed: "You’ll be able to create a workspace once your account is confirmed.",
    notProvided: "Not provided",
    createWorkspace: "Create workspace",
    setupWorkspace: "Set up the company workspace for this account.",
    companyName: "Company name",
    workspaceId: "Workspace ID",
    rncOptional: "RNC (optional)",
    workspaceDetails: "Workspace details",
    activeWorkspace: "Your active company workspace.",
    installAddon: "Install Addon",
    workspaceManagement: "Workspace management"
  },
  admin: {
    administration: "Administration",
    adminSignIn: "Admin sign in",
    signInCopy: "Sign in to access the administration area.",
    login: "Login",
    people: "People",
    directory: "Directory",
    directoryCopy: "Review confirmation status and workspace access.",
    directorySummary: "Directory summary",
    totalAccounts: "Total accounts",
    allAccounts: "All user accounts",
    awaitingConfirmation: "Awaiting confirmation",
    requireReview: "Require review",
    userDirectory: "User directory",
    manageAccounts: "Manage account confirmation and workspaces.",
    searchPeople: "Search people",
    noAccounts: "No accounts yet.",
    createStart: "Create a user to start the directory.",
    createUser: "Create user",
    addPerson: "Add a person",
    createCopy: "Create an account and its initial company workspace.",
    person: "Person",
    ownerCopy: "The account owner for this workspace.",
    fullName: "Full name",
    emailAddress: "Email address",
    temporaryPassword: "Temporary password",
    passwordHelp: "At least 6 characters.",
    companyWorkspace: "Company workspace",
    workspaceHelp: "Lowercase letters, numbers, and underscores only.",
    saveUser: "Save user"
  },
  addons: {
    extensions: "Extensions",
    apps: "Apps",
    availableApps: "Available apps",
    catalogCopy: "Extend your workspace with server-managed business tools.",
    available: "available",
    installedAddons: "ADDONS INSTALADOS",
    installed: "Installed",
    install: "Install",
    uninstall: "Uninstall"
  },
  receipts: {
    rnc: "RNC",
    encf: "NCF",
    date: "Date",
    store: "Store",
    customer: "Customer",
    document: "Document",
    celphone: "Celphone",
    salesperson: "Salesperson",
    copy: "COPY",
    creditInvoice: "CREDIT INVOICE",
    salesJournal: "SALES JOURNAL",
    description: "DESCRIPTION",
    itbis: "ITBIS",
    value: "VALUE",
    quoted: "Quoted",
    discount: "Discount",
    delivery: "Delivery",
    additionalInfo: "Additional info",
    purchaseSavings: "Purchase savings (discount)",
    articles: "Items",
    paidToDate: "Total paid to date",
    pendingBalance: "Pending balance",
    change: "Change",
    thanks: "Thank you for your purchase",
    receipt: "Receipt",
    consumerFinal: "FINAL CONSUMER",
    product: "PRODUCT",
    creditCard: "Credit Card",
    cash: "Cash"
  },
  js: {
    uploadInvalid: "Choose a valid image before saving.",
    uploadTooLarge: "Image must be 10 MB or smaller.",
    resizingImage: "Resizing image…",
    conversionFailed: "Image conversion failed",
    resizedReady: "{name} resized to {size} px and ready as Base64.",
    prepareFailed: "Image could not be prepared: {message}",
    logoRemoved: "Logo will be removed when you save.",
    imagePreparing: "Image is still being prepared. Please wait.",
    chooseValidOrRemove: "Choose a valid image or remove it before saving.",
    webUsbUnsupported: "WebUSB is not supported in this browser.",
    noWritableEndpoint: "Selected USB device has no writable endpoint.",
    printerDisconnected: "Printer is not connected.",
    noReceiptPrinter: "No receipt printer is connected.",
    sessionLoginFailed: "session login failed"
  },
  landing: {
    home: "Inicio",
    solution: "Solución",
    questions: "Preguntas",
    contact: "Contacto",
    signIn: "Iniciar sesión",
    openAccountMenu: "Abrir menú de cuenta",
    visitProfile: "Visita tu perfil",
    openNavigation: "Abrir menú de navegación",
    electronicInvoice: "Factura electrónica DGII",
    onePlace: "Controla todo en un solo lugar.",
    connects: "conecta ventas, inventario y clientes",
    invoiceAnywhere: "Factura con la DGII. Vende desde donde estés",
    everythingToSell: "Todo lo que necesitas para vender",
    easy: "Fácil de usar",
    easyCopy: "Empieza a vender sin una curva de aprendizaje complicada.",
    connected: "Todo conectado",
    connectedCopy: "Ventas, productos, clientes e inventario trabajan juntos.",
    accessAnywhere: "Acceso donde estés",
    accessCopy: "Mantén visibilidad de tu negocio desde tus dispositivos.",
    businessWithYou: "Tu negocio va contigo",
    growsWithYou: "Una solución que crece contigo",
    salesInventory: "Ventas e inventario",
    salesInventoryCopy: "Vende rápido y controla cada producto.",
    readyToGrow: "Preparado para crecer",
    aboutTigoo: "Preguntas sobre tigoo",
    knowTigoo: "Conoce tigoo",
    knowCopy: "Vende, controla y factura. Conoce todo lo que tigoo puede hacer.",
    visitTigoo: "Visitar tigoo",
    tigooView: "Vista de tigoo",
    simpler: "Tu negocio merece una solución más simple.",
    footer: "tigoo © 2026 · Ventas, inventario y facturación para avanzar.",
    legalInfo: "Información legal",
    privacy: "Política de privacidad",
    terms: "Términos de servicio",
    copyUrl: "Copiar la dirección web de tigoo"
  }
}

const es = {
  sequences: {"title": "Secuencias", "standard": "Secuencias de ventas", "rotation": "Secuencias con rotación mensual", "standardCopy": "Configura la numeración de facturas para ventas CF, VF y DV.", "rotationCopy": "Configura una ventana mensual con reutilización cíclica de números.", "empty": "No hay secuencias configuradas.", "base": "Base actual", "windowSize": "Valores disponibles", "allowedSteps": "Pasos permitidos", "period": "Mes", "step": "Paso", "lastNumber": "Último número", "estimated": "Monto mensual estimado", "allowed": "Monto mensual permitido", "average": "Monto promedio", "rotationHelp": "Los valores se calculan automáticamente. No se pueden editar la configuración del mes activo ni una base ya inicializada.", "loadFailed": "No se pudieron cargar las secuencias.", "saveFailed": "No se pudo guardar la secuencia.", "deleteFailed": "No se pudo eliminar la secuencia."},
  layout: {
    nav: {primary: "Navegación principal", pos: "POS", customers: "Clientes", invoices: "Reporte de facturas", inventory: "Inventario", orders: "Órdenes de compra", companySettings: "Configuración de empresa", users: "Usuarios", expand: "Expandir navegación", collapse: "Contraer navegación"},
    theme: {choose: "Elegir tema", label: "Tema", defaultLight: "Claro predeterminado", natureLight: "Naturaleza claro", natureDark: "Naturaleza oscuro", caffeineLight: "Café claro", caffeineDark: "Café oscuro", boldTechLight: "Tecnología claro", boldTechDark: "Tecnología oscuro", doom64Light: "Doom 64 claro", doom64Dark: "Doom 64 oscuro"},
    store: {choose: "Elegir tienda activa", active: "Tienda activa"},
    user: {menu: "Menú de usuario", openMenuFor: "Abrir menú para {name}", logout: "Cerrar sesión"},
    status: {system: "Estado del sistema", language: "Cambiar idioma de pantalla", printerDisconnected: "Impresora desconectada", printerConnecting: "Conectando impresora", printerConnected: "Impresora conectada", printerError: "Error de impresora", networkConnected: "Red conectada", networkDisconnected: "Red desconectada", loadingInvoiceDetails: "Cargando detalles de factura", loadingScreenContent: "Cargando contenido"}
  },
  common: {action: "Acción", actions: "Acciones", add: "Agregar", apply: "Aplicar", back: "Atrás", balance: "Balance", cancel: "Cancelar", cash: "Efectivo", choose: "Elegir", clear: "Limpiar", closed: "Cerrada", code: "Código", complete: "Completar", continue: "Continuar", create: "Crear", date: "Fecha", delete: "Eliminar", discount: "Descuento", documentId: "Documento", edit: "Editar", email: "Correo", item: "Artículo", items: "Artículos", loading: "Cargando...", name: "Nombre", no: "No", open: "Abierta", payment: "Pago", phone: "Teléfono", price: "Precio", product: "Producto", quantity: "Cantidad", save: "Guardar", status: "Estado", store: "Tienda", subtotal: "Subtotal", tax: "Impuesto", tax18: "Impuesto (18%)", total: "Total", user: "Usuario", view: "Ver", yes: "Sí"},
  pos: {
    pageTitle: "Tigoo Iniciar sesión",
    errors: {noStore: "No hay ninguna tienda disponible para esta cuenta.", storesUnavailable: "No se pudieron cargar las tiendas.", invalidLogin: "El usuario/correo o la contraseña son incorrectos.", selectStore: "Selecciona una tienda para continuar.", googleUnavailable: "El inicio con Google está disponible en la app de escritorio o móvil.", unableSignIn: "No se pudo iniciar sesión.", productsUnavailable: "No se pudieron cargar los productos."},
    login: {signIn: "Iniciar sesión", copy: "Usa tu usuario o correo y contraseña para continuar.", usernameOrEmail: "Usuario o correo", password: "Contraseña", store: "Tienda", selectStore: "Selecciona una tienda", continueWithGoogle: "Continuar con Google"},
    catalog: {pointOfSale: "Punto de venta", searchProducts: "Buscar productos o escanear un código", focusSearch: "Enfocar búsqueda de productos", catalog: "Catálogo", products: "Productos", loadingProducts: "Cargando productos…", noMatchingProducts: "No hay productos coincidentes.", scrollForMore: "Desplázate para más productos", productsLoaded: "productos cargados", viewSale: "Ver venta", addProduct: "Agregar {name}", unnamedProduct: "Producto sin nombre", sku: "SKU", tapToAdd: "Toca para agregar", stock: "Stock"},
    customers: {customers: "Clientes", customerList: "Lista de clientes", createCustomer: "Crear cliente", editCustomer: "Editar cliente", createCustomerTypo: "Crear cliente", searchCustomers: "Buscar clientes", searchCustomersPlaceholder: "Buscar clientes por nombre o teléfono", noCustomersFound: "No se encontraron clientes.", accountsCaption: "Cuentas de clientes y actividad de compra.", customerAction: "Acción de cliente", chooseCustomer: "Elegir: cliente", detail: "Detalle del cliente", backToCustomers: "Volver a clientes", loadingDetails: "Cargando detalles del cliente", account: "Cuenta del cliente", noDocumentId: "Sin documento", noPhone: "Sin teléfono", noAddress: "Sin dirección", noEmail: "Sin correo", retail: "Minorista", wholesale: "Mayorista", created: "Creado", pendingBalance: "Balance pendiente", totalInvoiced: "Total facturado", totalPaid: "Total pagado", outstandingBalance: "Balance por pagar", purchases: "Compras", lastPurchase: "Última compra", purchaseHistory: "Historial de compras", invoice: "Factura", salesPerson: "Vendedor", noPurchases: "No hay compras para este cliente.", addDialogCopy: "Agrega un cliente y úsalo en esta venta.", editDialogCopy: "Actualiza la cuenta y los datos de contacto de este cliente.", address: "Dirección", isWholesaler: "Es mayorista", saveCustomer: "Guardar cliente"},
    checkout: {checkout: "Checkout", customer: "Cliente", paymentCompletion: "Pago y cierre", backToSale: "Volver a la venta", progress: "Progreso del checkout", stepCustomer: "1. Cliente", stepPayment: "2. Pago", pickCustomer: "Elegir un cliente…", pickCustomerSpaced: "Elegir un cliente …", sequenceType: "Tipo de comprobante", consumerFinal: "Consumidor final", directSale: "Venta directa", fiscalVoucher: "Comprobante fiscal", delivery: "Entrega", freeAmount: "Monto libre", deliveryFreeAmount: "Monto libre de entrega", selectDeliveryFreeAmount: "Seleccionar monto libre de entrega", payOnCredit: "Vender a crédito", dueDate: "Fecha de vencimiento", payments: "Pagos", creditCard: "Tarjeta de crédito", removePayment: "Eliminar pago", addPayment: "Agregar pago", remaining: "Restante:", change: "Devuelta:", memoOptional: "Nota (opcional)", memoHelp: "Hasta 1000 caracteres.", paymentMethod: "Método de pago"},
    cart: {currentSale: "Venta actual", openCurrentSale: "Abrir venta actual", viewCustomerPurchases: "Ver compras del cliente", clearCustomer: "Quitar cliente", closeSale: "Cerrar venta", empty: "Tu orden está vacía. Selecciona un producto para empezar.", discountItem: "Aplicar descuento a este artículo", off: "desc.", sub: "Sub", each: "c/u", removeProduct: "Eliminar {name}", decreaseQuantity: "Disminuir cantidad", itemCount: "Cantidad de artículos", increaseQuantity: "Aumentar cantidad", discountSale: "Aplicar descuento a esta venta", applyOrderDiscount: "Aplicar descuento de orden. Presiona Enter.", clearTitle: "¿Limpiar esta orden?", clearDescription: "Se eliminarán todos los artículos y descuentos de línea.", clearOrder: "Limpiar orden"},
    discount: {lineItem: "Descuento de línea", order: "Descuento de orden", applyLine: "Aplicar un descuento", applyOrder: "Aplicar descuento a la orden", type: "Tipo de descuento", percentage: "Porcentaje de descuento", amount: "Monto de descuento", finalPrice: "Precio después del descuento", percentHelp: "Ingresa 0 para quitar este descuento.", amountHelp: "El monto aplica a toda esta línea.", orderAmountHelp: "El monto aplica a esta orden antes de la entrega.", finalPriceLineHelp: "Ingresa el precio final para toda esta línea.", finalPriceOrderHelp: "Ingresa el precio final de esta orden antes de la entrega.", amountLabel: "Monto", afterDiscount: "Después del descuento", applyDiscount: "Aplicar descuento", orderHelp: "Elige porcentaje o monto para esta orden."},
    purchases: {recent: "compras recientes", latest10: "Las 10 compras más recientes, primero la más nueva.", noPurchasesFound: "No se encontraron compras.", caption: "Historial de compras del cliente. Expande la cantidad para ver artículos vendidos.", productNumber: "Producto #{id}", saleNumber: "venta {id}"},
    print: {completed: "Venta completada", prompt: "¿Quieres imprimir el recibo?", printReceipt: "Imprimir recibo", skip: "Omitir"}
  },
  users: {users: "Usuarios", searchUsers: "Buscar usuarios", username: "Usuario", userType: "Tipo de usuario", employee: "Empleado", stores: "Tiendas", permissions: "Permisos", activeUser: "Usuario activo", active: "Activo", inactive: "Inactivo", createUser: "Crear usuario", deactivate: "Desactivar", details: "Detalles", firstName: "Nombre", lastName: "Apellido", newPassword: "Nueva contraseña (dejar en blanco para mantener la actual)", assignedStores: "Tiendas asignadas", noPermissions: "Sin permisos", noStores: "Sin tiendas", loading: "Cargando usuarios...", signinRequired: "Se requiere iniciar sesión para administrar usuarios.", permissionRequired: "Se requiere permiso de configuración de usuarios."},
  inventory: {operations: "Operaciones", inventory: "Inventario", searchProduct: "Buscar producto", archived: "Archivado", createProduct: "Crear producto", kpis: "KPIs de inventario y operaciones", valuation: "Valoración de inventario", companyTotal: "Total de empresa", negativeStock: "Stock negativo", uncostedInventory: "Inventario sin costo", stockout: "Sin stock", netSales: "Ventas netas", salesMix: "Mezcla de ventas", averageOrder: "Orden promedio", bestProducts: "Mejores productos", discountRate: "Tasa de descuento", paymentMix: "Mezcla de pagos", retention: "Retención", orderFlow: "Flujo de órdenes", noActivity: "Sin actividad", recordedPayments: "Pagos registrados", showFewerKpis: "Mostrar menos KPIs", showMoreKpis: "Mostrar más KPIs", byStore: "Inventario por tienda.", cost: "Costo", totalQuantity: "Cantidad total", currentQuantity: "Cantidad actual", active: "Activo", archiveIt: "Archivar", productStatus: "Estado del producto: {status}", update: "Actualizar", previousQuantity: "Cantidad anterior", lastUpdated: "Última actualización", updatedBy: "Actualizado por", noTraceHistory: "Sin historial todavía.", change: "Cambio", previousCurrent: "Anterior → Actual", context: "Contexto", to: "A:", from: "Desde:"},
  company: {title: "Configuración de empresa", accessRequired: "Se requiere acceso a configuración de empresa.", notFound: "No se encontró este elemento.", storeUnavailable: "La tienda seleccionada no está disponible.", loadFailed: "No se pudo cargar la configuración de empresa.", company: "Empresa", currentCompany: "Empresa actual", priceLists: "Listas de precios", priceListsCopy: "Administra las etiquetas usadas para precios de productos.", addPriceList: "Agregar lista de precios", noPriceLists: "Aún no hay listas de precios.", stores: "Tiendas", storesCopy: "Administra las ubicaciones de tiendas de tu empresa.", addStore: "Agregar tienda", noStores: "Aún no hay tiendas.", sequenceSets: "Secuencias", sequenceCopy: "Configura las secuencias usadas para ventas CF, VF y DV.", addSequence: "Agregar secuencia", noSequences: "No hay secuencias configuradas. Agrega CF, VF y DV para completar ventas.", providers: "Proveedores", providersCopy: "Administra proveedores usados en órdenes de compra.", addProvider: "Agregar proveedor", noProviders: "Aún no hay proveedores.", prefix: "Prefijo", digits: "Dígitos", increment: "Incremento", nextNumber: "Siguiente número", priceListLabel: "Etiqueta de lista de precios", providerName: "Nombre del proveedor", storeName: "Nombre de tienda", slogan: "Eslogan", address: "Dirección", storeLogoPreview: "Vista previa del logo", storeLogo: "Logo de tienda", uploadHelp: "Suelta una imagen aquí o elige un archivo (máx. 10 MB). Se redimensionará y guardará como Base64.", removeLogo: "Quitar logo"},
  reconciliation: {title: "Conciliación de caja", printReport: "Imprimir reporte", printTitle: "Imprimir conciliación", printDescription: "Imprime el recibo de conciliación de caja.", registerInputs: "Entradas de caja", cashier: "Cajero", openingCash: "Efectivo inicial", salesCount: "Cantidad de ventas", cashPayments: "Pagos en efectivo", cardPayments: "Pagos con tarjeta de crédito/débito", totalSales: "Ventas totales", expectedCashDrawer: "Efectivo esperado en caja", reportPreview: "Vista previa del reporte", receipt: "Recibo"},
  orders: {purchaseOrders: "Órdenes de compra", currentStore: "Órdenes de compra de la tienda actual.", orderId: "ID de orden", source: "Origen", destinationStore: "Tienda destino", orderCost: "Costo de orden", costDifference: "Diferencia de costo", lastUpdated: "Última actualización", createdBy: "Creado por", observedDiffers: "Las cantidades observadas difieren de las solicitadas", purchaseOrder: "Orden de compra", moveProducts: "Mover productos", backToOrders: "Volver a órdenes", orderNumber: "Orden #{id}", externalSource: "Origen externo", previous: "Anterior", next: "Siguiente", startCounting: "Iniciar conteo", processOrder: "Procesar orden", productsInOrder: "Productos en esta orden de compra.", requested: "Solicitado", observed: "Observado", itemCost: "Costo del artículo", createPurchaseOrder: "Crear orden de compra", moveProductsCopy: "Mueve productos desde una tienda origen a una tienda destino.", addProductsCopy: "Agrega productos y confirma las cantidades solicitadas.", originStore: "Tienda origen", sourceProvider: "Origen / proveedor", selectSource: "Selecciona un origen"},
  invoice: {title: "Reporte de facturas", sales: "Ventas", search: "Buscar facturas por cliente", searchPlaceholder: "Buscar por nombre de cliente", summary: "Resumen de estado de facturas", selectedStoreCaption: "Facturas de la tienda seleccionada.", dueDateHeader: "Fecha de vencimiento", walkIn: "Cliente ocasional", dueDate: "Vencimiento:", printCopy: "Imprimir copia", payments: "Pagos", method: "Método", amount: "Monto", noPayments: "No hay pagos registrados.", partial: "Parcial", printPayment: "Imprimir pago", lineItems: "Artículos", unitPrice: "Precio unitario", price: "PRECIO", paymentAmount: "Monto del pago", paid: "Pagado", payOff: "Saldar", anyDate: "Cualquier fecha", selectDateRange: "Seleccionar rango de fechas", chooseEndDate: "Elige una fecha final.", chooseStartEndDate: "Elige una fecha inicial y luego una final.", previousMonth: "Mes anterior", nextMonth: "Mes siguiente", applyRange: "Aplicar rango", cancelInvoiceTitle: "¿Cancelar factura?", cancelInvoiceCopy: "Esto restaura el inventario vendido. Esta acción no se puede deshacer desde el reporte.", selectedInvoice: "Factura seleccionada", keepInvoice: "Mantener factura", cancelInvoice: "Cancelar factura", printPaymentTitle: "Imprimir pago", printPaymentPrompt: "¿Quieres imprimir este recibo de pago?", printCopyTitle: "Imprimir copia", noReturnToPos: "No, volver al POS", cancelled: "Cancelada", confirmed: "Confirmada", pending: "Pendiente"},
  receipts: {rnc: "RNC", encf: "NCF", date: "Fecha", store: "Tienda", customer: "Cliente", document: "Documento", celphone: "Celular", salesperson: "Vendedor", copy: "COPIA", creditInvoice: "FACTURA A CREDITO", salesJournal: "DIARIO DE VENTAS", description: "DESCRIPCION", itbis: "ITBIS", value: "VALOR", quoted: "Cotizado", discount: "Descuento", delivery: "Entrega", additionalInfo: "Informacion adicional", purchaseSavings: "Ahorro en compra (descuento)", articles: "Articulos", paidToDate: "Total pagado a la fecha", pendingBalance: "Saldo pendiente", change: "Devuelta", thanks: "Gracias por su compra", receipt: "Recibo", consumerFinal: "CONSUMIDOR FINAL", product: "PRODUCTO", creditCard: "Tarjeta de credito", cash: "Efectivo"}
}

const pt = {
  sequences: {"title": "Sequências", "standard": "Sequências de vendas", "rotation": "Sequências com rotação mensal", "standardCopy": "Configure a numeração de faturas para vendas CF, VF e DV.", "rotationCopy": "Configure uma janela mensal com reutilização cíclica de números.", "empty": "Nenhuma sequência configurada.", "base": "Base atual", "windowSize": "Valores disponíveis", "allowedSteps": "Passos permitidos", "period": "Mês", "step": "Passo", "lastNumber": "Último número", "estimated": "Valor mensal estimado", "allowed": "Valor mensal permitido", "average": "Valor médio", "rotationHelp": "Os valores são calculados automaticamente. A configuração do mês ativo e uma base já inicializada não podem ser editadas.", "loadFailed": "Não foi possível carregar as sequências.", "saveFailed": "Não foi possível salvar a sequência.", "deleteFailed": "Não foi possível excluir a sequência."},
  layout: {
    nav: {primary: "Navegação principal", pos: "PDV", customers: "Clientes", invoices: "Relatório de faturas", inventory: "Estoque", orders: "Pedidos de compra", companySettings: "Configurações da empresa", users: "Usuários", expand: "Expandir navegação", collapse: "Recolher navegação"},
    theme: {choose: "Escolher tema", label: "Tema", defaultLight: "Claro padrão", natureLight: "Natureza claro", natureDark: "Natureza escuro", caffeineLight: "Café claro", caffeineDark: "Café escuro", boldTechLight: "Tecnologia claro", boldTechDark: "Tecnologia escuro", doom64Light: "Doom 64 claro", doom64Dark: "Doom 64 escuro"},
    store: {choose: "Escolher loja ativa", active: "Loja ativa"},
    user: {menu: "Menu do usuário", openMenuFor: "Abrir menu para {name}", logout: "Sair"},
    status: {system: "Status do sistema", language: "Alterar idioma de exibição", printerDisconnected: "Impressora desconectada", printerConnecting: "Conectando impressora", printerConnected: "Impressora conectada", printerError: "Erro da impressora", networkConnected: "Rede conectada", networkDisconnected: "Rede desconectada", loadingInvoiceDetails: "Carregando detalhes da fatura", loadingScreenContent: "Carregando conteúdo"}
  },
  common: {action: "Ação", actions: "Ações", add: "Adicionar", apply: "Aplicar", back: "Voltar", balance: "Saldo", cancel: "Cancelar", cash: "Dinheiro", choose: "Escolher", clear: "Limpar", closed: "Fechada", code: "Código", complete: "Concluir", continue: "Continuar", create: "Criar", date: "Data", delete: "Excluir", discount: "Desconto", documentId: "Documento", edit: "Editar", email: "E-mail", item: "Item", items: "Itens", loading: "Carregando...", name: "Nome", no: "Não", open: "Aberta", payment: "Pagamento", phone: "Telefone", price: "Preço", product: "Produto", quantity: "Quantidade", save: "Salvar", status: "Status", store: "Loja", subtotal: "Subtotal", tax: "Imposto", tax18: "Imposto (18%)", total: "Total", user: "Usuário", view: "Ver", yes: "Sim"},
  pos: {
    pageTitle: "Tigoo Entrar",
    errors: {noStore: "Nenhuma loja está disponível para esta conta.", storesUnavailable: "Não foi possível carregar as lojas.", invalidLogin: "O usuário/e-mail ou a senha está incorreto.", selectStore: "Selecione uma loja para continuar.", googleUnavailable: "O login com Google está disponível no app desktop ou móvel.", unableSignIn: "Não foi possível entrar.", productsUnavailable: "Não foi possível carregar os produtos."},
    login: {signIn: "Entrar", copy: "Use seu usuário ou e-mail e senha para continuar.", usernameOrEmail: "Usuário ou e-mail", password: "Senha", store: "Loja", selectStore: "Selecione uma loja", continueWithGoogle: "Continuar com Google"},
    catalog: {pointOfSale: "Ponto de venda", searchProducts: "Buscar produtos ou escanear código", focusSearch: "Focar busca de produtos", catalog: "Catálogo", products: "Produtos", loadingProducts: "Carregando produtos…", noMatchingProducts: "Nenhum produto encontrado.", scrollForMore: "Role para mais produtos", productsLoaded: "produtos carregados", viewSale: "Ver venda", addProduct: "Adicionar {name}", unnamedProduct: "Produto sem nome", sku: "SKU", tapToAdd: "Toque para adicionar", stock: "Estoque"},
    customers: {customers: "Clientes", customerList: "Lista de clientes", createCustomer: "Criar cliente", editCustomer: "Editar cliente", createCustomerTypo: "Criar cliente", searchCustomers: "Buscar clientes", searchCustomersPlaceholder: "Buscar clientes por nome ou telefone", noCustomersFound: "Nenhum cliente encontrado.", accountsCaption: "Contas de clientes e atividade de compra.", customerAction: "Ação do cliente", chooseCustomer: "Escolher: cliente", detail: "Detalhe do cliente", backToCustomers: "Voltar para clientes", loadingDetails: "Carregando detalhes do cliente", account: "Conta do cliente", noDocumentId: "Sem documento", noPhone: "Sem telefone", noAddress: "Sem endereço", noEmail: "Sem e-mail", retail: "Varejo", wholesale: "Atacado", created: "Criado", pendingBalance: "Saldo pendente", totalInvoiced: "Total faturado", totalPaid: "Total pago", outstandingBalance: "Saldo em aberto", purchases: "Compras", lastPurchase: "Última compra", purchaseHistory: "Histórico de compras", invoice: "Fatura", salesPerson: "Vendedor", noPurchases: "Nenhuma compra encontrada para este cliente.", addDialogCopy: "Adicione um cliente e use-o nesta venda.", editDialogCopy: "Atualize a conta e os dados de contato deste cliente.", address: "Endereço", isWholesaler: "É atacadista", saveCustomer: "Salvar cliente"},
    checkout: {checkout: "Checkout", customer: "Cliente", paymentCompletion: "Pagamento e conclusão", backToSale: "Voltar à venda", progress: "Progresso do checkout", stepCustomer: "1. Cliente", stepPayment: "2. Pagamento", pickCustomer: "Escolher cliente…", pickCustomerSpaced: "Escolher cliente …", sequenceType: "Tipo de sequência", consumerFinal: "Consumidor final", directSale: "Venda direta", fiscalVoucher: "Comprovante fiscal", delivery: "Entrega", freeAmount: "Valor livre", deliveryFreeAmount: "Valor livre de entrega", selectDeliveryFreeAmount: "Selecionar valor livre de entrega", payOnCredit: "Vender a crédito", dueDate: "Data de vencimento", payments: "Pagamentos", creditCard: "Cartão de crédito", removePayment: "Remover pagamento", addPayment: "Adicionar pagamento", remaining: "Restante:", change: "Troco:", memoOptional: "Observação (opcional)", memoHelp: "Até 1000 caracteres.", paymentMethod: "Método de pagamento"},
    cart: {currentSale: "Venda atual", openCurrentSale: "Abrir venda atual", viewCustomerPurchases: "Ver compras do cliente", clearCustomer: "Remover cliente", closeSale: "Fechar venda", empty: "Seu pedido está vazio. Selecione um produto para começar.", discountItem: "Aplicar desconto a este item", off: "desc.", sub: "Sub", each: "cada", removeProduct: "Remover {name}", decreaseQuantity: "Diminuir quantidade", itemCount: "Quantidade de itens", increaseQuantity: "Aumentar quantidade", discountSale: "Aplicar desconto a esta venda", applyOrderDiscount: "Aplicar desconto do pedido. Pressione Enter.", clearTitle: "Limpar este pedido?", clearDescription: "Todos os itens e descontos de linha serão removidos.", clearOrder: "Limpar pedido"},
    discount: {lineItem: "Desconto do item", order: "Desconto do pedido", applyLine: "Aplicar desconto", applyOrder: "Aplicar desconto ao pedido", type: "Tipo de desconto", percentage: "Percentual de desconto", amount: "Valor do desconto", finalPrice: "Preco apos desconto", percentHelp: "Digite 0 para remover este desconto.", amountHelp: "O valor se aplica a toda esta linha.", orderAmountHelp: "O valor se aplica a este pedido antes da entrega.", finalPriceLineHelp: "Digite o preco final para toda esta linha.", finalPriceOrderHelp: "Digite o preco final deste pedido antes da entrega.", amountLabel: "Valor", afterDiscount: "Após desconto", applyDiscount: "Aplicar desconto", orderHelp: "Escolha percentual ou valor para este pedido."},
    purchases: {recent: "compras recentes", latest10: "As 10 compras mais recentes, mais nova primeiro.", noPurchasesFound: "Nenhuma compra encontrada.", caption: "Histórico de compras do cliente. Expanda a quantidade para ver os itens vendidos.", productNumber: "Produto #{id}", saleNumber: "venda {id}"},
    print: {completed: "Venda concluída", prompt: "Deseja imprimir o recibo?", printReceipt: "Imprimir recibo", skip: "Pular"}
  },
  users: {users: "Usuários", searchUsers: "Buscar usuários", username: "Usuário", userType: "Tipo de usuário", employee: "Funcionário", stores: "Lojas", permissions: "Permissões", activeUser: "Usuário ativo", active: "Ativo", inactive: "Inativo", createUser: "Criar usuário", deactivate: "Desativar", details: "Detalhes", firstName: "Nome", lastName: "Sobrenome", newPassword: "Nova senha (deixe em branco para manter a atual)", assignedStores: "Lojas atribuídas", noPermissions: "Sem permissões", noStores: "Sem lojas", loading: "Carregando usuários...", signinRequired: "É preciso entrar para gerenciar usuários.", permissionRequired: "Permissão de configuração de usuários é necessária."},
  inventory: {operations: "Operações", inventory: "Estoque", searchProduct: "Buscar produto", archived: "Arquivado", createProduct: "Criar produto", kpis: "KPIs de estoque e operações", valuation: "Valoração do estoque", companyTotal: "Total da empresa", negativeStock: "Estoque negativo", uncostedInventory: "Estoque sem custo", stockout: "Sem estoque", netSales: "Vendas líquidas", salesMix: "Mix de vendas", averageOrder: "Pedido médio", bestProducts: "Melhores produtos", discountRate: "Taxa de desconto", paymentMix: "Mix de pagamentos", retention: "Retenção", orderFlow: "Fluxo de pedidos", noActivity: "Sem atividade", recordedPayments: "Pagamentos registrados", showFewerKpis: "Mostrar menos KPIs", showMoreKpis: "Mostrar mais KPIs", byStore: "Estoque por loja.", cost: "Custo", totalQuantity: "Quantidade total", currentQuantity: "Quantidade atual", active: "Ativo", archiveIt: "Arquivar", productStatus: "Status do produto: {status}", update: "Atualizar", previousQuantity: "Quantidade anterior", lastUpdated: "Última atualização", updatedBy: "Atualizado por", noTraceHistory: "Ainda sem histórico.", change: "Alteração", previousCurrent: "Anterior → Atual", context: "Contexto", to: "Para:", from: "De:"},
  company: {title: "Configurações da empresa", accessRequired: "Acesso às configurações da empresa é necessário.", notFound: "Este item não foi encontrado.", storeUnavailable: "A loja selecionada não está disponível.", loadFailed: "Não foi possível carregar as configurações da empresa.", company: "Empresa", currentCompany: "Empresa atual", priceLists: "Listas de preços", priceListsCopy: "Gerencie os rótulos usados para preços dos produtos.", addPriceList: "Adicionar lista de preços", noPriceLists: "Ainda não há listas de preços.", stores: "Lojas", storesCopy: "Gerencie as localizações das lojas da empresa.", addStore: "Adicionar loja", noStores: "Ainda não há lojas.", sequenceSets: "Sequências", sequenceCopy: "Defina as sequências usadas para vendas CF, VF e DV.", addSequence: "Adicionar sequência", noSequences: "Nenhuma sequência configurada. Adicione CF, VF e DV para completar vendas.", providers: "Fornecedores", providersCopy: "Gerencie fornecedores usados em pedidos de compra.", addProvider: "Adicionar fornecedor", noProviders: "Ainda não há fornecedores.", prefix: "Prefixo", digits: "Dígitos", increment: "Incremento", nextNumber: "Próximo número", priceListLabel: "Rótulo da lista de preços", providerName: "Nome do fornecedor", storeName: "Nome da loja", slogan: "Slogan", address: "Endereço", storeLogoPreview: "Prévia do logo", storeLogo: "Logo da loja", uploadHelp: "Solte uma imagem aqui ou escolha um arquivo (máx. 10 MB). Ela será redimensionada e salva como Base64.", removeLogo: "Remover logo"},
  reconciliation: {title: "Conciliação de caixa", printReport: "Imprimir relatório", printTitle: "Imprimir conciliação", printDescription: "Imprima o recibo de conciliação de caixa.", registerInputs: "Entradas do caixa", cashier: "Caixa", openingCash: "Dinheiro inicial", salesCount: "Quantidade de vendas", cashPayments: "Pagamentos em dinheiro", cardPayments: "Pagamentos com cartão de crédito/débito", totalSales: "Total de vendas", expectedCashDrawer: "Dinheiro esperado no caixa", reportPreview: "Prévia do relatório", receipt: "Recibo"},
  orders: {purchaseOrders: "Pedidos de compra", currentStore: "Pedidos de compra da loja atual.", orderId: "ID do pedido", source: "Origem", destinationStore: "Loja destino", orderCost: "Custo do pedido", costDifference: "Diferença de custo", lastUpdated: "Última atualização", createdBy: "Criado por", observedDiffers: "As quantidades observadas diferem das solicitadas", purchaseOrder: "Pedido de compra", moveProducts: "Mover produtos", backToOrders: "Voltar aos pedidos", orderNumber: "Pedido #{id}", externalSource: "Origem externa", previous: "Anterior", next: "Próximo", startCounting: "Iniciar contagem", processOrder: "Processar pedido", productsInOrder: "Produtos neste pedido de compra.", requested: "Solicitado", observed: "Observado", itemCost: "Custo do item", createPurchaseOrder: "Criar pedido de compra", moveProductsCopy: "Mova produtos de uma loja de origem para uma loja de destino.", addProductsCopy: "Adicione produtos e confirme as quantidades solicitadas.", originStore: "Loja origem", sourceProvider: "Origem / fornecedor", selectSource: "Selecione uma origem"},
  invoice: {title: "Relatório de faturas", sales: "Vendas", search: "Buscar faturas por cliente", searchPlaceholder: "Buscar por nome do cliente", summary: "Resumo de status das faturas", selectedStoreCaption: "Faturas da loja selecionada.", dueDateHeader: "Vencimento", walkIn: "Cliente avulso", dueDate: "Vencimento:", printCopy: "Imprimir cópia", payments: "Pagamentos", method: "Método", amount: "Valor", noPayments: "Nenhum pagamento registrado.", partial: "Parcial", printPayment: "Imprimir pagamento", lineItems: "Itens", unitPrice: "Preço unitário", price: "Preço", paymentAmount: "Valor do pagamento", paid: "Pago", payOff: "Quitar", anyDate: "Qualquer data", selectDateRange: "Selecionar intervalo de datas", chooseEndDate: "Escolha uma data final.", chooseStartEndDate: "Escolha uma data inicial e depois uma final.", previousMonth: "Mês anterior", nextMonth: "Próximo mês", applyRange: "Aplicar intervalo", cancelInvoiceTitle: "Cancelar fatura?", cancelInvoiceCopy: "Isso restaura o estoque vendido. Esta ação não pode ser desfeita pelo relatório.", selectedInvoice: "Fatura selecionada", keepInvoice: "Manter fatura", cancelInvoice: "Cancelar fatura", printPaymentTitle: "Imprimir pagamento", printPaymentPrompt: "Deseja imprimir este recibo de pagamento?", printCopyTitle: "Imprimir cópia", noReturnToPos: "Não, voltar ao PDV", cancelled: "Cancelada", confirmed: "Confirmada", pending: "Pendente"},
  receipts: {rnc: "RNC", encf: "NCF", date: "Data", store: "Loja", customer: "Cliente", document: "Documento", celphone: "Celular", salesperson: "Vendedor", copy: "COPIA", creditInvoice: "FATURA A CREDITO", salesJournal: "DIARIO DE VENDAS", description: "DESCRICAO", itbis: "IMPOSTO", value: "VALOR", quoted: "Cotado", discount: "Desconto", delivery: "Entrega", additionalInfo: "Informacao adicional", purchaseSavings: "Economia na compra (desconto)", articles: "Itens", paidToDate: "Total pago ate agora", pendingBalance: "Saldo pendente", change: "Troco", thanks: "Obrigado pela compra", receipt: "Recibo", consumerFinal: "CONSUMIDOR FINAL", product: "PRODUTO", creditCard: "Cartao de credito", cash: "Dinheiro"}
}

const dictionaries = {en, es: merge(en, es), pt: merge(en, pt)}

const pageTitleKeys = {
  "Tigoo Sign in": "pos.pageTitle",
  "Point of Sale": "pos.catalog.pointOfSale",
  "Payment & completion": "pos.checkout.paymentCompletion",
  "Tigoo Customers": "pos.customers.customers",
  "Invoice report": "invoice.title",
  "Invoice Report": "invoice.title",
  "Cash Reconciliation": "reconciliation.title",
  "Inventory": "layout.nav.inventory",
  "Purchase Orders": "orders.purchaseOrders",
  "Tigoo Company settings": "company.title",
  "Tigoo Sequences": "sequences.title",
  "Tigoo Users": "users.users"
}

export function getLanguage() {
  try {
    const saved = localStorage.getItem(LANGUAGE_KEY)
    return Object.hasOwn(LANGUAGES, saved) ? saved : "en"
  } catch {
    return "en"
  }
}

export function setLanguage(language) {
  const next = Object.hasOwn(LANGUAGES, language) ? language : "en"
  try {
    localStorage.setItem(LANGUAGE_KEY, next)
  } catch {
  }
  document.documentElement.lang = next
  document.documentElement.dataset.language = next
  window.dispatchEvent(new CustomEvent("pos:language-changed", {detail: {language: next}}))
  return next
}

export function t(key, params = {}, language = getLanguage()) {
  const value = key.split(".").reduce((node, part) => node?.[part], dictionaries[language]) ?? key
  return typeof value === "string" ? interpolate(value, params) : key
}

export function money(value, language = getLanguage()) {
  const config = LANGUAGES[language] || LANGUAGES.en
  const amount = Number(value) || 0
  const parts = new Intl.NumberFormat(config.locale, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  }).formatToParts(Math.abs(amount))
  const number = parts.map(part => part.value).join("")
  return `${amount < 0 ? "-" : ""}$ ${number}`
}

export function translatePage(root = document) {
  root.querySelectorAll("[data-i18n]").forEach(element => {
    element.textContent = t(element.dataset.i18n, datasetParams(element))
  })
  root.querySelectorAll("[data-i18n-placeholder]").forEach(element => {
    element.setAttribute("placeholder", t(element.dataset.i18nPlaceholder, datasetParams(element)))
  })
  root.querySelectorAll("[data-i18n-aria-label]").forEach(element => {
    element.setAttribute("aria-label", t(element.dataset.i18nAriaLabel, datasetParams(element)))
  })
  root.querySelectorAll("[data-i18n-title]").forEach(element => {
    element.setAttribute("title", t(element.dataset.i18nTitle, datasetParams(element)))
  })
  root.querySelectorAll("[data-i18n-data-label]").forEach(element => {
    element.setAttribute("data-label", t(element.dataset.i18nDataLabel, datasetParams(element)))
  })
  root.querySelectorAll("[data-i18n-alt]").forEach(element => {
    element.setAttribute("alt", t(element.dataset.i18nAlt, datasetParams(element)))
  })
  root.querySelectorAll("[data-i18n-value]").forEach(element => {
    element.value = t(element.dataset.i18nValue, datasetParams(element))
  })
  root.querySelectorAll("[data-money]").forEach(element => {
    element.textContent = money(element.dataset.money)
  })
  syncPageTitle()
  syncLanguageMenu(root)
}

export function initI18n() {
  window.PosI18n = {getLanguage, setLanguage, t, money, translatePage}
  document.documentElement.lang = getLanguage()
  document.documentElement.dataset.language = getLanguage()
  observePageTitle()
  document.addEventListener("click", event => {
    const button = event.target.closest("[data-language]")
    if (!button) return
    const menu = button.closest("details")
    setLanguage(button.dataset.language)
    translatePage(document)
    if (menu) menu.open = false
  })
  window.addEventListener("pos:language-changed", () => translatePage(document))
  translatePage(document)
}

function syncLanguageMenu(root) {
  root.querySelectorAll("[data-language]").forEach(button => {
    button.setAttribute("aria-current", String(button.dataset.language === getLanguage()))
    button.setAttribute("aria-pressed", String(button.dataset.language === getLanguage()))
  })
}

function syncPageTitle() {
  const key = pageTitleKeys[document.title] || document.documentElement.dataset.pageTitleKey
  if (!key) return
  document.documentElement.dataset.pageTitleKey = key
  const translated = t(key)
  if (document.title !== translated) document.title = translated
}

function observePageTitle() {
  const title = document.querySelector("title")
  if (!title) return
  const observer = new MutationObserver(() => syncPageTitle())
  observer.observe(title, {childList: true, characterData: true, subtree: true})
}

function datasetParams(element) {
  if (!element.dataset.i18nParams) return {}
  try {
    return JSON.parse(element.dataset.i18nParams)
  } catch {
    return {}
  }
}

function interpolate(value, params) {
  return value.replace(/\{(\w+)\}/g, (_, key) => params[key] ?? "")
}

function merge(base, patch) {
  const output = {...base}
  for (const [key, value] of Object.entries(patch)) {
    output[key] = value && typeof value === "object" && !Array.isArray(value) ? merge(base[key] || {}, value) : value
  }
  return output
}
