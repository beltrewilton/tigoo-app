// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket, Presence} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/pos_server"
import topbar from "../vendor/topbar"
import {receiptPrinter} from "./receipt_printer/service"
import {initI18n, money, t, translatePage} from "./i18n"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const POS_LANGUAGE_KEY = "pos-display-language"
const POS_THEME_KEY = "pos-theme"
const POS_STORE_KEY = "pos-selected-store-id"
const POS_DRAFT_KEY_PREFIX = "pos-sale-draft"
const POS_CATALOG_VIEW_KEY = "pos-catalog-view"
const PRODUCT_IMAGE_DB = "pos-product-images"
const PRODUCT_IMAGE_STORE = "images"
const PRINT_RELAY_SESSION_KEY = "pos.printRelay.sessionId"
let activePrintRelay = null

function liveSocketParams() {
  const catalogView = getStoredValue(POS_CATALOG_VIEW_KEY)
  const language = getStoredValue(POS_LANGUAGE_KEY)
  const theme = getStoredValue(POS_THEME_KEY)
  const storeId = getStoredValue(POS_STORE_KEY)
  return {
    _csrf_token: csrfToken,
    catalog_view: catalogView === "cards" || catalogView === "table" ? catalogView : "cards",
    language,
    theme,
    store_id: storeId
  }
}

const hooks = {
  LoginScreen: window.LoginScreenHook,
  CompanySettings: window.CompanySettingsHook,
  Sequences: {
    mounted() {
      this.editing = this.el.dataset.editing
      requestAnimationFrame(() => this.el.querySelector("#sequences-title")?.focus())
    },
    updated() {
      const editing = this.el.dataset.editing
      if (editing === this.editing) return
      this.editing = editing
      const target = editing
        ? this.el.querySelector("#sequence-settings-form input:not(:disabled)")
        : this.el.querySelector("#sequences-title")
      requestAnimationFrame(() => target?.focus())
    }
  },
  CustomerDialog: dialogHook(),
  ProductDialog: productDialogHook(),
  CustomerScreen: {
    mounted() {
      this.customerScrollTop = 0
      this.handleEvent("customer:detail-opened", () => {
        const catalog = this.el.querySelector(".catalog-panel")
        this.customerScrollTop = catalog?.scrollTop || 0
        if (catalog) catalog.scrollTop = 0
        requestAnimationFrame(() => this.el.querySelector("#customer-detail-title")?.focus())
      })
      this.handleEvent("customer:list-restored", () => {
        requestAnimationFrame(() => {
          const catalog = this.el.querySelector(".catalog-panel")
          if (catalog) catalog.scrollTop = this.customerScrollTop || 0
          this.el.querySelector("#customers-table-body [phx-click='open_customer_detail']")?.focus()
        })
      })
      requestAnimationFrame(() => {
        this.el.querySelector("#customer-search")?.focus()
      })
    },
    updated() { translatePage(this.el) }
  },
  UsersScreen: {
    mounted() {
      this.handleEvent("users:focus-title", () => {
        requestAnimationFrame(() => this.el.querySelector("#users-title")?.focus())
      })
      requestAnimationFrame(() => this.el.querySelector("#users-search")?.focus())
    },
    updated() { translatePage(this.el) }
  },
  InventoryScreen: {
    mounted() {
      requestAnimationFrame(() => this.el.querySelector("#inventory-search")?.focus())
    },
    updated() { translatePage(this.el) }
  },
  InfiniteInvoices: {
    mounted() {
      this.observer = new IntersectionObserver(entries => {
        if (entries.some(entry => entry.isIntersecting)) this.pushEvent("load_more")
      }, {rootMargin: "360px"})
      this.observer.observe(this.el)
    },
    destroyed() { this.observer?.disconnect() }
  },
  InvoiceReport: {
    mounted() {
      installPrinterEvents(this)
      this.fixed = this.el.querySelector(".invoice-report-fixed")
      this.syncStickyOffset = () => this.el.querySelector("#invoice-report")?.style.setProperty("--invoice-fixed-height", `${this.fixed?.offsetHeight || 0}px`)
      this.resizeObserver = new ResizeObserver(this.syncStickyOffset)
      if (this.fixed) this.resizeObserver.observe(this.fixed)
      this.syncStickyOffset()
      this.onPointerDown = event => {
        if (!this.el.querySelector(".invoice-date-picker")?.contains(event.target)) this.pushEvent("close_calendar")
      }
      document.addEventListener("pointerdown", this.onPointerDown)
      requestAnimationFrame(() => this.el.querySelector("#invoice-search")?.focus())
    },
    updated() {
      syncPrintLogoCache(this.el)
      this.syncStickyOffset?.()
      translatePage(this.el)
    },
    destroyed() {
      this.resizeObserver?.disconnect()
      document.removeEventListener("pointerdown", this.onPointerDown)
    }
  },
  InfiniteCatalog: {
    mounted() {
      this.observer = new IntersectionObserver(entries => {
        if (entries.some(entry => entry.isIntersecting)) this.pushEvent("load_more_products")
      }, {rootMargin: "360px"})
      this.observer.observe(this.el)
    },
    destroyed() { this.observer?.disconnect() }
  },
  ProductImageCache: {
    mounted() {
      this.tenant = this.el.dataset.tenant || tenantId()
      this.loggedProductImages = new Set()
      this.persistedProductImages = new Set()
      this.visibleProductImages = new Map()
      this.sync = () => syncProductImageCache(this)
      this.handleEvent("product-images:sync", this.sync)
      this.syncSoon = () => {
        cancelAnimationFrame(this.syncFrame)
        this.syncFrame = requestAnimationFrame(this.sync)
      }
      this.imageObserver = new MutationObserver(this.syncSoon)
      this.imageObserver.observe(this.el.closest(".catalog-content") || this.el, {
        childList: true,
        subtree: true
      })
      requestAnimationFrame(this.sync)
    },
    beforeUpdate() {
      this.visibleProductImages = captureVisibleProductImages()
    },
    updated() {
      this.tenant = this.el.dataset.tenant || tenantId()
      restoreVisibleProductImages(this.visibleProductImages)
      requestAnimationFrame(this.sync)
    },
    destroyed() {
      cancelAnimationFrame(this.syncFrame)
      this.imageObserver?.disconnect()
    }
  },
  PurchaseOrderLines: purchaseOrderLinesHook(),
  PurchaseOrders: purchaseOrdersHook(),
  OrderProductDialog: dialogHook(),
  PosTheme: {
    mounted() {
      this.onTheme = event => document.documentElement.dataset.theme = event.detail.theme
      window.addEventListener("pos:set-theme", this.onTheme)
    },
    destroyed() { window.removeEventListener("pos:set-theme", this.onTheme) }
  },
  StorePreference: {
    mounted() {
      this.syncStore = () => {
        const savedStoreId = getStoredValue(POS_STORE_KEY)
        if (savedStoreId && savedStoreId !== this.el.dataset.storeId) {
          this.pushEvent("change_store", {store_id: savedStoreId})
        }
      }
      this.persistStore = event => {
        const button = event.target.closest("[phx-click='change_store'][phx-value-store_id]")
        if (!button) return
        setStoredValue(POS_STORE_KEY, button.getAttribute("phx-value-store_id"))
      }
      document.addEventListener("click", this.persistStore)
      this.syncStore()
    },
    updated() {
      setStoredValue(POS_STORE_KEY, this.el.dataset.storeId)
    },
    destroyed() {
      document.removeEventListener("click", this.persistStore)
    }
  },
  PrinterStatus: {
    mounted() {
      installPrinterStatus(this.el)
    },
    destroyed() {
      uninstallPrinterStatus(this.el)
    }
  },
  PrinterSession: {
    mounted() {
      installPrinterSession(this.el)
    },
    destroyed() {
      uninstallPrinterSession(this.el)
    }
  },
  NetworkStatus: {
    mounted() {
      installNetworkStatus(this.el)
    },
    destroyed() {
      uninstallNetworkStatus(this.el)
    }
  },
  PrintRelay: {
    mounted() {
      installPrintRelay(this)
    },
    updated() {
      updatePrintRelay(this)
    },
    destroyed() {
      uninstallPrintRelay(this)
    }
  },
  CreditDueDateForm: {
    mounted() {
      this.value = this.el.querySelector("#sale-credit-due-date")?.value || ""
      this.sync = () => {
        const input = this.el.querySelector("#sale-credit-due-date")
        this.value = input?.value || ""
        const complete = this.el.querySelector("#complete-sale")
        if (complete) complete.disabled = !(input?.value && input.validity.valid)
      }
      this.el.addEventListener("input", this.sync)
      this.el.addEventListener("change", this.sync)
      this.sync()
    },
    updated() {
      const input = this.el.querySelector("#sale-credit-due-date")
      if (input && this.value && input.value !== this.value) input.value = this.value
      this.sync()
    },
    destroyed() {
      this.el.removeEventListener("input", this.sync)
      this.el.removeEventListener("change", this.sync)
    }
  },
  PosShell: {
    mounted() {
      installPrinterEvents(this)
      pushClientInfo(this)
      this.draftKey = posDraftKey(this.el)
      const draft = readStoredJson(this.draftKey)
      if (draft) this.pushEvent("restore_pos_draft", draft)
      const catalogView = getStoredValue(POS_CATALOG_VIEW_KEY)
      if (catalogView === "cards" || catalogView === "table") {
        this.pushEvent("set_catalog_view", {view: catalogView})
      }
      this.mobileCartMedia = window.matchMedia?.("(max-width: 640px)")
      this.syncMobileCartState = () => syncMobileCartState(this.el, this.mobileCartMedia?.matches === true)
      this.mobileCartMedia?.addEventListener?.("change", this.syncMobileCartState)
      this.handleEvent("pos:draft-changed", ({draft}) => {
        if (!draft || !Array.isArray(draft.cart) || draft.cart.length === 0) {
          removeStoredValue(this.draftKey)
          return
        }
        writeStoredJson(this.draftKey, draft)
      })
      requestAnimationFrame(() => this.el.querySelector("#product-search")?.focus())
      this.onKeydown = event => {
        if (event.key === "Escape" && this.el.dataset.mobileCartOpen === "true") this.pushEvent("close_mobile_cart")
      }
      this.onClick = event => {
        const button = event.target.closest(".catalog-view-toggle[phx-value-view]")
        if (button) {
          const view = button.getAttribute("phx-value-view")
          setStoredValue(POS_CATALOG_VIEW_KEY, view)
          document.documentElement.classList.toggle("pos-catalog-view-table", view === "table")
        }
      }
      document.addEventListener("keydown", this.onKeydown)
      this.el.addEventListener("click", this.onClick)
      this.syncMobileCartState()
    },
    updated() {
      syncPrintLogoCache(this.el)
      this.syncMobileCartState?.()
      translatePage(this.el)
    },
    destroyed() {
      document.removeEventListener("keydown", this.onKeydown)
      this.el.removeEventListener("click", this.onClick)
      this.mobileCartMedia?.removeEventListener?.("change", this.syncMobileCartState)
    }
  },
  CartAmounts: {
    mounted() {
      this.recalculate = () => calculateCart(this.el)
      this.onQuantityClick = event => {
        const button = event.target.closest("[data-quantity-action]")
        if (!button) return
        const input = button.closest(".quantity-control")?.querySelector(".quantity-input")
        if (!input) return
        const delta = button.dataset.quantityAction === "increase" ? 1 : -1
        input.value = String(Math.max(1, (Number.parseInt(input.value, 10) || 1) + delta))
        this.recalculate()
      }
      this.el.addEventListener("input", this.recalculate)
      this.el.addEventListener("click", this.onQuantityClick)
      this.handleEvent("pos:cart-bump", ({id}) => {
        const line = document.getElementById(`cart-line-${id}`)
        if (!line) return
        line.classList.remove("bump")
        void line.offsetWidth
        line.classList.add("bump")
        calculateCart(line.closest("#order-panel"))
      })
      this.recalculate()
    },
    updated() { this.recalculate() },
    destroyed() {
      this.el.removeEventListener("input", this.recalculate)
      this.el.removeEventListener("click", this.onQuantityClick)
    }
  },
  DiscountPreview: {
    mounted() {
      this.updatePreview = () => updateDiscountPreview(this.el)
      this.el.querySelector("#discount-input")?.addEventListener("input", this.updatePreview)
      this.onTypeClick = event => {
        if (event.target.closest("[data-clear-discount]")) {
          const input = this.el.querySelector("#discount-input")
          input.value = ""
          this.updatePreview()
          input.focus()
          return
        }
        const button = event.target.closest("[data-discount-type]")
        if (!button) return
        const input = this.el.querySelector("#discount-input")
        const base = Number.parseFloat(this.el.dataset.discountBase) || 0
        const currentType = this.el.dataset.discountType
        const currentDeduction = discountDeduction(currentType, input?.value, base)
        const type = button.dataset.discountType
        this.el.dataset.discountType = type
        this.el.querySelector("#discount-type").value = type
        this.el.querySelectorAll("[data-discount-type]").forEach(entry => {
          const active = entry === button
          entry.dataset.variant = active ? "default" : "secondary"
          entry.setAttribute("aria-pressed", String(active))
        })
        input.max = type === "percent" ? "100" : (type === "final_price" ? String(base.toFixed(2)) : "")
        input.value = discountInputForType(type, currentDeduction, base)
        this.el.querySelector("#discount-input-label").textContent = discountInputLabel(type)
        this.el.querySelector("#discount-help").textContent = discountInputHelp(type, this.el.dataset.discountTarget === "line")
        this.updatePreview()
        input.focus()
      }
      this.el.addEventListener("click", this.onTypeClick)
      this.updatePreview()
    },
    updated() { this.updatePreview() },
    destroyed() {
      this.el.querySelector("#discount-input")?.removeEventListener("input", this.updatePreview)
      this.el.removeEventListener("click", this.onTypeClick)
    }
  },
  DiscountDialog: {
    mounted() {
      if (!this.el.open) this.el.showModal()
      requestAnimationFrame(() => this.el.querySelector("#discount-input")?.focus())
      this.preventCancel = event => event.preventDefault()
      this.el.addEventListener("cancel", this.preventCancel)
    },
    destroyed() { this.el.removeEventListener("cancel", this.preventCancel) }
  },
  CustomerPurchases: {
    mounted() {
      this.onClick = event => {
        const trigger = event.target.closest("[data-customer-purchase-details]")
        if (!trigger || !this.el.contains(trigger)) return
        const details = document.getElementById(`customer-purchase-items-${trigger.dataset.customerPurchaseDetails}`)
        if (!details) return
        const expanded = trigger.getAttribute("aria-expanded") === "true"
        trigger.setAttribute("aria-expanded", String(!expanded))
        trigger.querySelector(".customer-purchase-disclosure").textContent = expanded ? "▸" : "▾"
        details.hidden = expanded
      }
      this.el.addEventListener("click", this.onClick)
    },
    destroyed() { this.el.removeEventListener("click", this.onClick) }
  },
  PaymentAmounts: {
    mounted() {
      this.money = value => money(value)
      this.updateSummary = () => {
        const total = Number(this.el.dataset.saleTotal) || 0
        const paid = [...this.el.querySelectorAll(".payment-line input")].reduce((sum, input) => sum + (Number(input.value) || 0), 0)
        const remaining = Math.max(0, total - paid)
        const change = Math.max(0, paid - total)
        const checkoutTotal = this.el.closest(".checkout-stage")?.querySelector("#checkout-total")
        const balance = this.el.parentElement.querySelector("#payment-balance")
        let changeLabel = this.el.parentElement.querySelector("#payment-change")
        if (!changeLabel) {
          changeLabel = this.el.parentElement.querySelector("[data-client-payment-change]")
          if (!changeLabel) {
            changeLabel = document.createElement("p")
            changeLabel.className = "payment-change"
            changeLabel.dataset.clientPaymentChange = ""
            changeLabel.hidden = true
            balance?.insertAdjacentElement("afterend", changeLabel)
          }
        }
        const complete = this.el.closest(".checkout-stage")?.querySelector("#complete-sale")
        if (checkoutTotal) checkoutTotal.textContent = this.money(total)
        if (balance) balance.textContent = `${t("pos.checkout.remaining")} ${this.money(remaining)}`
        if (changeLabel) {
          changeLabel.hidden = change === 0
          changeLabel.textContent = change ? `${t("pos.checkout.change")} ${this.money(change)}` : ""
        }
        if (complete) complete.disabled = paid < total
      }
      this.onInput = event => {
        const input = event.target.closest(".payment-line input")
        if (!input || !this.el.contains(input)) return
        const line = input.closest(".payment-line")
        const previous = Number(input.dataset.previousAmount) || 0
        const entered = Number(input.value) || 0
        const sourceId = line.dataset.splitSource
        const source = sourceId && this.el.querySelector(`[data-payment-line-id="${sourceId}"] input`)
        if (source) {
          const change = Math.round((entered - previous) * 100) / 100
          const total = Number(this.el.dataset.saleTotal) || 0
          const totalBeforeChange = [...this.el.querySelectorAll(".payment-line input")].reduce((sum, node) => sum + (Number(node.value) || 0), 0) - entered + previous
          const changeAbsorbed = change < 0 ? Math.min(-change, Math.max(0, totalBeforeChange - total)) : 0
          const transferred = change > 0 ? Math.min(change, Number(source.value) || 0) : change + changeAbsorbed
          source.value = String(Math.max(0, Math.round(((Number(source.value) || 0) - transferred) * 100) / 100))
          source.dataset.previousAmount = source.value
        }
        input.dataset.previousAmount = String(entered)
        this.updateSummary()
      }
      this.currentPayments = () => [...this.el.querySelectorAll(".payment-line")].map(line => {
        const type = line.querySelector("select")?.value
        const amount = Number(line.querySelector("input")?.value) || 0
        return {type, amount}
      }).filter(payment => ["CASH", "CC"].includes(payment.type) && payment.amount > 0)
      this.onComplete = event => {
        const button = event.target.closest("#complete-sale")
        if (!button || button.disabled) return
        event.preventDefault()
        event.stopPropagation()
        this.pushEvent("complete_sale", {payments: this.currentPayments()})
      }
      this.el.addEventListener("input", this.onInput)
      this.el.closest(".checkout-stage")?.addEventListener("click", this.onComplete, true)
      this.onCartTotal = event => {
        const total = Number(event.detail?.total)
        if (!Number.isFinite(total)) return
        this.el.dataset.saleTotal = String(total)
        this.updateSummary()
      }
      window.addEventListener("pos:checkout-total", this.onCartTotal)
      this.onLanguage = () => this.updateSummary()
      window.addEventListener("pos:language-changed", this.onLanguage)
      this.updateSummary()
    },
    updated() { this.updateSummary() },
    destroyed() {
      this.el.removeEventListener("input", this.onInput)
      this.el.closest(".checkout-stage")?.removeEventListener("click", this.onComplete, true)
      window.removeEventListener("pos:checkout-total", this.onCartTotal)
      window.removeEventListener("pos:language-changed", this.onLanguage)
    }
  },
  FlashToast: {
    mounted() {
      this.el.showPopover?.()
      this.dismissTimer = setTimeout(() => this.pushEvent("clear_pos_flash"), 4000)
    },
    destroyed() { clearTimeout(this.dismissTimer) }
  }
}
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: liveSocketParams,
  hooks: {...colocatedHooks, ...hooks},
})

initI18n()

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())
window.addEventListener("phx:page-loading-stop", () => translatePage(document))

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

function printerStatusLabel(state) {
  return {
    disconnected: t("layout.status.printerDisconnected"),
    connecting: t("layout.status.printerConnecting"),
    connected: t("layout.status.printerConnected"),
    error: t("layout.status.printerError")
  }[state] || t("layout.status.printerDisconnected")
}

function installPrinterStatus(element) {
  if (!element) return
  element.printerStatusInstallCount = (element.printerStatusInstallCount || 0) + 1
  if (element.printerStatusHandler) return
  element.printerStatusTarget = element.matches?.("[data-printer-status]")
    ? element
    : element.querySelector("[data-printer-status]")
  if (!element.printerStatusTarget) return
  element.printerStatusHandler = event => {
    const detail = receiptPrinter.statusDetail(event.detail)
    const state = detail.state
    element.printerStatusTarget.dataset.status = state
    element.printerStatusTarget.setAttribute("aria-label", printerStatusLabel(state))
    element.printerStatusTarget.title = detail.device?.productName || printerStatusLabel(state)
  }
  element.printerStatusClickHandler = async () => {
    try {
      await receiptPrinter.connect()
    } catch (error) {
    }
  }
  receiptPrinter.addEventListener("status", element.printerStatusHandler)
  element.printerStatusTarget.addEventListener("click", element.printerStatusClickHandler)
  element.printerStatusHandler({detail: receiptPrinter.statusDetail()})
}

function uninstallPrinterStatus(element) {
  if (!element?.printerStatusHandler) return
  element.printerStatusInstallCount = Math.max((element.printerStatusInstallCount || 1) - 1, 0)
  if (element.printerStatusInstallCount > 0) return
  receiptPrinter.removeEventListener("status", element.printerStatusHandler)
  element.printerStatusTarget?.removeEventListener("click", element.printerStatusClickHandler)
  delete element.printerStatusHandler
  delete element.printerStatusClickHandler
  delete element.printerStatusTarget
  delete element.printerStatusInstallCount
}

function installPrinterSession(element) {
  if (!element || element.printerSessionInstalled) return
  element.printerSessionInstalled = true
  element.printerSessionRefreshHandler = () => {
    const state = receiptPrinter.statusDetail().state
    if (document.hidden || state === "connected" || state === "connecting") return
    receiptPrinter.reconnect().catch(() => {})
  }
  element.printerSessionUsbDisconnectHandler = event => {
    if (!receiptPrinter.isConnected()) return
    receiptPrinter.usbDisconnected(event.device)
  }
  window.addEventListener("focus", element.printerSessionRefreshHandler)
  document.addEventListener("visibilitychange", element.printerSessionRefreshHandler)
  navigator.usb?.addEventListener("connect", element.printerSessionRefreshHandler)
  navigator.usb?.addEventListener("disconnect", element.printerSessionUsbDisconnectHandler)
  element.printerSessionRefreshHandler()
}

function uninstallPrinterSession(element) {
  if (!element?.printerSessionInstalled) return
  window.removeEventListener("focus", element.printerSessionRefreshHandler)
  document.removeEventListener("visibilitychange", element.printerSessionRefreshHandler)
  navigator.usb?.removeEventListener("connect", element.printerSessionRefreshHandler)
  navigator.usb?.removeEventListener("disconnect", element.printerSessionUsbDisconnectHandler)
  delete element.printerSessionRefreshHandler
  delete element.printerSessionUsbDisconnectHandler
  delete element.printerSessionInstalled
}

function networkStatusLabel(state) {
  return state === "connected" ? t("layout.status.networkConnected") : t("layout.status.networkDisconnected")
}

function setNetworkStatus(element, state) {
  element.dataset.status = state
  element.setAttribute("aria-label", networkStatusLabel(state))
  element.title = networkStatusLabel(state)
}

function installNetworkStatus(element) {
  if (!element) return
  element.networkStatusInstallCount = (element.networkStatusInstallCount || 0) + 1
  if (element.networkStatusRefreshHandler) return
  element.networkStatusRefreshHandler = async () => {
    if (document.hidden) return
    element.networkStatusAbortController?.abort()
    element.networkStatusAbortController = new AbortController()
    const timeout = setTimeout(() => element.networkStatusAbortController.abort(), 2_000)
    try {
      await fetch(`${window.location.origin}/?_network_status=${Date.now()}`, {
        method: "HEAD",
        cache: "no-store",
        signal: element.networkStatusAbortController.signal
      })
      setNetworkStatus(element, "connected")
    } catch (error) {
      setNetworkStatus(element, "disconnected")
    } finally {
      clearTimeout(timeout)
    }
  }
  window.addEventListener("online", element.networkStatusRefreshHandler)
  window.addEventListener("offline", element.networkStatusRefreshHandler)
  window.addEventListener("focus", element.networkStatusRefreshHandler)
  document.addEventListener("visibilitychange", element.networkStatusRefreshHandler)
  setNetworkStatus(element, navigator.onLine ? "connected" : "disconnected")
  element.networkStatusRefreshHandler()
  element.networkStatusInterval = setInterval(element.networkStatusRefreshHandler, 5_000)
}

function uninstallNetworkStatus(element) {
  if (!element?.networkStatusRefreshHandler) return
  element.networkStatusInstallCount = Math.max((element.networkStatusInstallCount || 1) - 1, 0)
  if (element.networkStatusInstallCount > 0) return
  window.removeEventListener("online", element.networkStatusRefreshHandler)
  window.removeEventListener("offline", element.networkStatusRefreshHandler)
  window.removeEventListener("focus", element.networkStatusRefreshHandler)
  document.removeEventListener("visibilitychange", element.networkStatusRefreshHandler)
  element.networkStatusAbortController?.abort()
  clearInterval(element.networkStatusInterval)
  delete element.networkStatusAbortController
  delete element.networkStatusRefreshHandler
  delete element.networkStatusInterval
  delete element.networkStatusInstallCount
}

function installPrinterEvents(hook) {
  syncPrintLogoCache(hook.el)
  hook.handleEvent("printer:print-receipt", payload => {
    const prepared = preparePrintPayload(payload)
    const sale = prepared.local.receipt || prepared.local.sale
    console.log("[printer] LiveView event printer:print-receipt", {requestId: payload.request_id, sequence: sale?.sequence, hasCopyLabel: sale?.copy === true})
    return hook.printWithResult(payload.request_id, prepared.relay, () => receiptPrinter.printReceipt(sale))
  })
  hook.handleEvent("printer:print-payment", payload => {
    const prepared = preparePrintPayload(payload)
    console.log("[printer] LiveView event printer:print-payment", {requestId: payload.request_id, sequence: prepared.local.sale?.sequence, paymentId: prepared.local.payment?.id})
    return hook.printWithResult(payload.request_id, prepared.relay, () => receiptPrinter.printPayment(prepared.local))
  })
  hook.handleEvent("printer:reprint-invoice", payload => {
    const prepared = preparePrintPayload(payload)
    const sale = prepared.local.invoice || prepared.local.receipt || prepared.local.sale
    console.log("[printer] LiveView event printer:reprint-invoice", {requestId: payload.request_id, sequence: sale?.sequence})
    return hook.printWithResult(payload.request_id, prepared.relay, () => receiptPrinter.reprintInvoice(sale))
  })
  hook.handleEvent("printer:print-reconciliation", payload => {
    const prepared = preparePrintPayload(payload)
    const reconciliation = prepared.local.reconciliation || prepared.local.receipt
    return hook.printWithResult(payload.request_id, prepared.relay, () => receiptPrinter.printReconciliation(reconciliation))
  })
  hook.printWithResult = async (requestId, payload, operation) => {
    try {
      if (shouldRelayPrint() && activePrintRelay) await activePrintRelay.print(payload)
      else await operation()
      if (requestId) hook.pushEvent("printer_result", {request_id: requestId, status: "success"})
    } catch (error) {
      if (requestId) hook.pushEvent("printer_result", {request_id: requestId, status: "failed", message: error.message})
    }
  }
}

function syncMobileCartState(root, mobileViewport) {
  const panel = root.querySelector("#order-panel")
  const catalog = root.querySelector(".catalog-panel")
  const modalOpen = root.dataset.mobileCartOpen === "true" && mobileViewport

  if (modalOpen) {
    panel?.setAttribute("role", "dialog")
    panel?.setAttribute("aria-modal", "true")
    catalog?.setAttribute("inert", "")
  } else {
    panel?.removeAttribute("role")
    panel?.removeAttribute("aria-modal")
    catalog?.removeAttribute("inert")
  }
}

function installPrintRelay(hook) {
  syncPrintLogoCache(hook.el)
  const token = hook.el.dataset.printRelayToken
  const storeId = hook.el.dataset.storeId
  printDebug("installPrintRelay", {hasToken: Boolean(token), storeId, client: clientDeviceInfo(), printer: receiptPrinter.statusDetail()})
  if (!token || !storeId) return

  hook.printRelayToken = token
  hook.printRelayStoreId = storeId
  hook.printRelay = createLiveViewPrintRelay({
    token,
    storeId,
    onRequest: payload => handleRemotePrintRequest(hook, payload)
  })
  hook.printRelay.connect()
  activePrintRelay = hook.printRelay
}

function updatePrintRelay(hook) {
  syncPrintLogoCache(hook.el)
  const token = hook.el.dataset.printRelayToken
  const storeId = hook.el.dataset.storeId
  printDebug("updatePrintRelay", {storeId, previousStoreId: hook.printRelayStoreId, tokenChanged: token !== hook.printRelayToken})
  if (token === hook.printRelayToken && storeId === hook.printRelayStoreId) return
  uninstallPrintRelay(hook)
  installPrintRelay(hook)
}

function uninstallPrintRelay(hook) {
  printDebug("uninstallPrintRelay", {storeId: hook.printRelayStoreId, hasRelay: Boolean(hook.printRelay)})
  if (activePrintRelay === hook.printRelay) activePrintRelay = null
  hook.printRelay?.close()
  hook.printRelay = null
  hook.printRelayToken = null
  hook.printRelayStoreId = null
}

function createLiveViewPrintRelay({token, storeId, onRequest}) {
  const socket = new Socket("/socket", {
    params: {token},
    logger: (kind, message, data) => printDebug("phoenix-socket", {kind, message, data})
  })
  let presence = {}
  let lastPrinterMeta = null
  const joinPayload = {
    device: relayDevice(),
    session_id: printRelaySessionId(),
    tenant: tenantId(),
    logo_version: cachedPrintLogoVersion(tenantId()),
    ...clientDeviceInfo(),
    ...desktopPrinterMeta()
  }
  printDebug("createLiveViewPrintRelay", {storeId, joinPayload, printer: receiptPrinter.statusDetail()})
  const channel = socket.channel(`print-relay:${storeId}`, joinPayload)
  const relay = {socket, channel, targets: []}
  const syncTargets = targets => {
    relay.targets = [...(targets || [])].sort((a, b) => String(a.session_id).localeCompare(String(b.session_id)))
    printDebug("syncTargets", {count: relay.targets.length, targets: relay.targets})
  }
  const publishPrinter = () => {
    printDebug("publishPrinter:attempt", {channelState: channel.state, localCapability: hasLocalPrinterCapability(), canPrintLocally: canPrintLocally(), status: receiptPrinter.statusDetail()})
    if (!hasLocalPrinterCapability() || channel.state !== "joined") return
    const meta = desktopPrinterMeta()
    if (samePrinterMeta(lastPrinterMeta, meta)) return
    lastPrinterMeta = meta
    printRelayPush(channel, "printer_status", meta)
      .receive("ok", response => {
        printDebug("printer_status:ok", response)
        syncTargets(response.targets)
      })
      .receive("error", response => printDebug("printer_status:error", response))
      .receive("timeout", () => printDebug("printer_status:timeout"))
  }
  const refreshPrinter = async () => {
    if (document.hidden) return
    printDebug("refreshPrinter:attempt", {channelState: channel.state, localCapability: hasLocalPrinterCapability(), connected: receiptPrinter.isConnected()})
    if (!hasLocalPrinterCapability() || channel.state !== "joined") return
    if (receiptPrinter.isConnected()) {
      publishPrinter()
      return
    }
    await receiptPrinter.reconnect().catch(() => false)
    publishPrinter()
  }

  channel.on("presence_state", state => {
    printDebug("presence_state", state)
    presence = Presence.syncState(presence, state)
    syncTargets(printRelayTargets(presence))
  })
  channel.on("presence_diff", diff => {
    printDebug("presence_diff", diff)
    presence = Presence.syncDiff(presence, diff)
    syncTargets(printRelayTargets(presence))
  })
  channel.on("print_request", payload => {
    printDebug("print_request:received", payload)
    onRequest(payload)
  })
  channel.on("print_result", payload => {
    printDebug("print_result:received", payload)
  })
  receiptPrinter.addEventListener("status", publishPrinter)
  window.addEventListener("focus", refreshPrinter)
  document.addEventListener("visibilitychange", refreshPrinter)

  return {
    connect() {
      printDebug("relay.connect", {storeId, joinPayload})
      socket.connect()
      channel.join()
        .receive("ok", response => {
          printDebug("relay.join:ok", response)
          syncTargets(response.targets)
          refreshPrinter()
        })
        .receive("error", error => {
          printDebug("relay.join:error", error)
          console.warn("[printer] print relay unavailable", error)
        })
        .receive("timeout", () => printDebug("relay.join:timeout"))
    },
    close() {
      printDebug("relay.close", {storeId, channelState: channel.state})
      receiptPrinter.removeEventListener("status", publishPrinter)
      window.removeEventListener("focus", refreshPrinter)
      document.removeEventListener("visibilitychange", refreshPrinter)
      channel.leave()
      socket.disconnect()
    },
    async print(payload) {
      printDebug("relay.print:attempt", {payload, targets: relay.targets, local: {capability: hasLocalPrinterCapability(), connected: receiptPrinter.isConnected()}})
      if (relay.targets.length === 0) throw new Error("No desktop receipt printer is available for this store.")
      const target = relay.targets[0]
      const requestId = payload.request_id || `print-${Date.now()}`
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error("Remote print request timed out."))
        }, 20_000)
        printRelayPush(channel, "print", {request_id: requestId, target_session_id: target.session_id, job: stripPrintLogos({...payload, tenant: tenantId(), logo_version: cachedPrintLogoVersion(tenantId())})})
          .receive("ok", response => {
            clearTimeout(timeout)
            printDebug("relay.print:queued", response)
            resolve(response)
          })
          .receive("error", response => {
            clearTimeout(timeout)
            printDebug("relay.print:error", response)
            reject(new Error(response.reason || "Remote print request failed."))
          })
          .receive("timeout", () => {
            clearTimeout(timeout)
            printDebug("relay.print:timeout", {requestId})
            reject(new Error("Remote print request timed out."))
          })
      })
    }
  }
}

function samePrinterMeta(left, right) {
  if (!left || !right) return false
  return left.label === right.label &&
    left.printer === right.printer &&
    left.printer_online === right.printer_online
}

function shouldRelayPrint() {
  const relay = !canPrintLocally()
  printDebug("shouldRelayPrint", {relay, localCapability: hasLocalPrinterCapability(), connected: receiptPrinter.isConnected(), client: clientDeviceInfo()})
  return relay
}

function relayDevice() {
  if (canPrintLocally()) return "desktop"
  const info = clientDeviceInfo()
  return info.mobile || info.tablet ? "mobile" : "desktop"
}

function desktopPrinterMeta() {
  const status = receiptPrinter.statusDetail()
  const device = status.device
  const printerOnline = canPrintLocally()
  return {
    label: printerOnline ? "Desktop Web POS" : clientDeviceInfo().label,
    printer: device?.printerModel || device?.productName || device?.manufacturerName || "Receipt printer",
    printer_online: printerOnline
  }
}

function hasLocalPrinterCapability() {
  return Boolean(navigator.usb)
}

function canPrintLocally() {
  return hasLocalPrinterCapability() && receiptPrinter.isConnected()
}

function clientDeviceInfo() {
  const userAgent = navigator.userAgent || ""
  const uaData = navigator.userAgentData
  const platform = navigator.platform || uaData?.platform || ""
  const maxTouchPoints = navigator.maxTouchPoints || 0
  const uaMobile = uaData?.mobile === true || /Android|webOS|iPhone|iPod|BlackBerry|IEMobile|Opera Mini/i.test(userAgent)
  const tablet = /iPad|Tablet/i.test(userAgent) || (platform === "MacIntel" && maxTouchPoints > 1)
  const mobile = uaMobile && !tablet

  return {
    user_agent: userAgent,
    platform,
    mobile,
    tablet,
    touch_points: maxTouchPoints,
    webusb: hasLocalPrinterCapability(),
    label: mobile || tablet ? "Mobile POS" : "Desktop Web POS"
  }
}

function pushClientInfo(hook) {
  if (hook.clientInfoPushed) return
  hook.clientInfoPushed = true
  const info = clientDeviceInfo()
  printDebug("pushClientInfo", info)
  hook.pushEvent("client_info", info)
}

function preparePrintPayload(payload) {
  const local = hydratePrintLogos(payload)
  const relay = stripPrintLogos(local)
  return {local, relay}
}

function hydratePrintLogos(payload) {
  return withPrintLogo(payload, cachedPrintLogo(payload?.tenant || tenantId(), payload?.logo_version || ""))
}

function stripPrintLogos(payload) {
  return withPrintLogo(payload, null)
}

function withPrintLogo(payload, logo) {
  const next = clonePrintPayload(payload || {})
  for (const key of ["receipt", "sale", "invoice", "reconciliation"]) {
    if (next[key]?.store) {
      if (logo) next[key].store.logo = logo
      else delete next[key].store.logo
    }
  }
  if (next.sale?.store && next.payment) {
    if (logo) next.sale.store.logo = logo
    else delete next.sale.store.logo
  }
  next.tenant = next.tenant || tenantId()
  next.logo_version = cachedPrintLogoVersion(next.tenant)
  return next
}

function clonePrintPayload(payload) {
  if (typeof structuredClone === "function") return structuredClone(payload)
  return JSON.parse(JSON.stringify(payload))
}

function syncPrintLogoCache(element) {
  const tenant = element?.dataset?.tenant || tenantId()
  if (!tenant) return
  const logo = element?.dataset?.printLogo || ""
  const version = element?.dataset?.printLogoVersion || ""
  const signature = `${tenant}:${version}`
  if (element.printLogoCacheSignature === signature) return
  element.printLogoCacheSignature = signature

  try {
    if (!logo || !version) {
      localStorage.removeItem(printLogoKey(tenant))
      localStorage.removeItem(printLogoVersionKey(tenant))
      printDebug("logoCache:cleared", {tenant})
      return
    }

    if (localStorage.getItem(printLogoVersionKey(tenant)) === version) return
    localStorage.setItem(printLogoKey(tenant), logo)
    localStorage.setItem(printLogoVersionKey(tenant), version)
    printDebug("logoCache:updated", {tenant, version, bytes: logo.length})
  } catch (error) {
    printDebug("logoCache:unavailable", {tenant, message: error.message})
  }
}

function cachedPrintLogo(tenant, expectedVersion = "") {
  if (!tenant) return null
  try {
    if (expectedVersion && localStorage.getItem(printLogoVersionKey(tenant)) !== expectedVersion) return null
    const logo = localStorage.getItem(printLogoKey(tenant))
    if (logo && /^data:image\/[a-zA-Z0-9.+-]+;base64,/.test(logo)) return logo
    localStorage.removeItem(printLogoKey(tenant))
    localStorage.removeItem(printLogoVersionKey(tenant))
  } catch (error) {
    printDebug("logoCache:readFailed", {tenant, message: error.message})
  }
  return null
}

function cachedPrintLogoVersion(tenant) {
  if (!tenant) return ""
  try {
    return localStorage.getItem(printLogoVersionKey(tenant)) || ""
  } catch {
    return ""
  }
}

function printLogoKey(tenant) {
  return `pos:print-logo:${tenant}`
}

function printLogoVersionKey(tenant) {
  return `pos:print-logo-version:${tenant}`
}

function tenantId() {
  return document.querySelector("[data-tenant]")?.dataset.tenant || ""
}

function printRelayPush(channel, event, payload) {
  if (!channel) {
    printDebug("channel.push:missing-channel", {event, payload})
    return null
  }
  printDebug("channel.push", {topic: channel.topic, event, payload})
  return channel.push(event, payload)
}

function printDebug(message, detail = {}) {
  console.log(`[print-relay] ${message}`, detail)
}

function printRelaySessionId() {
  const existing = getSessionValue(PRINT_RELAY_SESSION_KEY)
  if (existing) return existing
  const id = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`
  setSessionValue(PRINT_RELAY_SESSION_KEY, id)
  return id
}

function printRelayTargets(presence) {
  return Object.entries(presence || {}).flatMap(([sessionId, value]) =>
    (value.metas || [])
      .filter(meta => meta.device === "desktop" && meta.printer_online === true)
      .map(meta => ({session_id: sessionId, ...meta}))
  )
}

function handleRemotePrintRequest(hook, payload) {
  const job = hydratePrintLogos(payload.job || {request_id: payload.request_id, receipt: payload.receipt, tenant: payload.tenant, logo_version: payload.logo_version})
  printDebug("remotePrint:job", {requestId: payload.request_id, job})
  return printJob(job)
    .then(() => {
      printDebug("remotePrint:success", {requestId: payload.request_id})
      return printRelayPush(hook.printRelay?.channel, "print_result", {request_id: payload.request_id, status: "success"})
        ?.receive("ok", response => printDebug("remotePrint:resultAck", response))
        ?.receive("error", response => printDebug("remotePrint:resultError", response))
        ?.receive("timeout", () => printDebug("remotePrint:resultTimeout", {requestId: payload.request_id}))
    })
    .catch(error => {
      printDebug("remotePrint:failed", {requestId: payload.request_id, message: error.message})
      return printRelayPush(hook.printRelay?.channel, "print_result", {request_id: payload.request_id, status: "failed", message: error.message})
        ?.receive("ok", response => printDebug("remotePrint:failedAck", response))
        ?.receive("error", response => printDebug("remotePrint:failedError", response))
        ?.receive("timeout", () => printDebug("remotePrint:failedTimeout", {requestId: payload.request_id}))
    })
}

function printJob(payload) {
  if (payload.reconciliation) return receiptPrinter.printReconciliation(payload.reconciliation)
  if (payload.payment) return receiptPrinter.printPayment(payload)
  if (payload.invoice) return receiptPrinter.reprintInvoice(payload.invoice)
  return receiptPrinter.printReceipt(payload.receipt || payload.sale)
}

function getStoredValue(key) {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function setStoredValue(key, value) {
  try {
    if (value === null || value === undefined || value === "") localStorage.removeItem(key)
    else localStorage.setItem(key, String(value))
  } catch {
  }
}

function getSessionValue(key) {
  try {
    return sessionStorage.getItem(key)
  } catch {
    return null
  }
}

function setSessionValue(key, value) {
  try {
    if (value === null || value === undefined || value === "") sessionStorage.removeItem(key)
    else sessionStorage.setItem(key, String(value))
  } catch {
  }
}

function removeStoredValue(key) {
  try {
    localStorage.removeItem(key)
  } catch {
  }
}

function readStoredJson(key) {
  try {
    return JSON.parse(localStorage.getItem(key) || "null")
  } catch {
    return null
  }
}

function writeStoredJson(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch {
  }
}

function productImageCacheKey(tenant, productId, dateCreate) {
  return `${tenant || "default"}:${productId}:${dateCreate}`
}

function productImageDb() {
  if (!("indexedDB" in window)) return Promise.reject(new Error("IndexedDB is unavailable."))
  if (window.productImageDbPromise) return window.productImageDbPromise
  window.productImageDbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(PRODUCT_IMAGE_DB, 1)
    request.onupgradeneeded = () => {
      request.result.createObjectStore(PRODUCT_IMAGE_STORE, {keyPath: "key"})
    }
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
  return window.productImageDbPromise
}

async function readCachedProductImage(tenant, productId, dateCreate) {
  const db = await productImageDb()
  const key = productImageCacheKey(tenant, productId, dateCreate)
  return new Promise((resolve, reject) => {
    const tx = db.transaction(PRODUCT_IMAGE_STORE, "readonly")
    const request = tx.objectStore(PRODUCT_IMAGE_STORE).get(key)
    request.onsuccess = () => resolve(request.result?.src || null)
    request.onerror = () => reject(request.error)
  })
}

async function writeCachedProductImage(tenant, productId, dateCreate, src) {
  if (!src || !src.startsWith("data:image/")) return false
  const db = await productImageDb()
  const key = productImageCacheKey(tenant, productId, dateCreate)
  await new Promise((resolve, reject) => {
    const tx = db.transaction(PRODUCT_IMAGE_STORE, "readwrite")
    tx.objectStore(PRODUCT_IMAGE_STORE).put({key, tenant, product_id: String(productId), date_create: String(dateCreate), src})
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
  })
  return true
}

function productImageSelectorValue(value) {
  if (window.CSS?.escape) return CSS.escape(String(value))
  return String(value).replace(/["\\]/g, "\\$&")
}

function setProductImageElement(image, src) {
  image.src = src
  image.hidden = false
  document
    .querySelectorAll(`[data-product-image-placeholder="${productImageSelectorValue(image.dataset.productImageId)}"]`)
    .forEach(element => { element.hidden = true })
}

function productImageDomKey(image) {
  const productId = image.dataset.productImageId
  const cacheKey = image.dataset.productImageCacheKey || ""
  return productId ? `${productId}:${cacheKey}` : null
}

function captureVisibleProductImages(root = document) {
  const state = new Map()
  root.querySelectorAll("[data-product-image-id]").forEach(image => {
    const key = productImageDomKey(image)
    if (!key || image.hidden) return
    const src = image.currentSrc || image.getAttribute("src") || ""
    if (src) state.set(key, src)
  })
  return state
}

function restoreVisibleProductImages(state, root = document) {
  if (!state?.size) return
  root.querySelectorAll("[data-product-image-id]").forEach(image => {
    const src = state.get(productImageDomKey(image))
    if (src) setProductImageElement(image, src)
  })
}

function logProductImageSource(hook, source, productId, dateCreate) {
  const key = `${source}:${productId}:${dateCreate}`
  if (hook.loggedProductImages?.has(key)) return
  hook.loggedProductImages?.add(key)
  console.log(`Product image loaded from ${source}`, {productId, dateCreate})
}

async function syncProductImageCache(hook) {
  const tenant = hook.tenant || tenantId()
  const productImages = [...document.querySelectorAll("[data-product-image-id]")]
  const images = productImages.filter(image => image.dataset.productImageCacheKey)
  const unversioned = productImages.filter(image => !image.dataset.productImageCacheKey)
  console.log("Product image cache sync", {
    count: images.length,
    unversioned: unversioned.length,
    dataImages: productImages.filter(image => (image.currentSrc || image.getAttribute("src") || "").startsWith("data:image/")).length,
    tenant
  })
  unversioned.forEach(image => {
    const current = image.currentSrc || image.getAttribute("src") || ""
    console.log("Product image skipped cache because version is missing", {
      productId: image.dataset.productImageId,
      fromServer: current.startsWith("data:image/")
    })
  })

  await Promise.all(images.map(async image => {
    const productId = image.dataset.productImageId
    const dateCreate = image.dataset.productImageCacheKey
    if (!tenant || !productId || !dateCreate) return

    const current = image.currentSrc || image.getAttribute("src") || ""
    if (current.startsWith("data:image/")) {
      logProductImageSource(hook, "server", productId, dateCreate)
      try {
        await writeCachedProductImage(tenant, productId, dateCreate, current)
        setProductImageElement(image, current)
        notifyProductImagePersisted(hook, productId, dateCreate)
      } catch {
      }
      return
    }

    try {
      const cached = await readCachedProductImage(tenant, productId, dateCreate)
      if (cached && cached.startsWith("data:image/")) {
        logProductImageSource(hook, "IndexedDB", productId, dateCreate)
        setProductImageElement(image, cached)
      }
    } catch {
    }
  }))
}

function notifyProductImagePersisted(hook, productId, dateCreate) {
  const key = `${productId}:${dateCreate}`
  if (hook.persistedProductImages?.has(key)) return
  hook.persistedProductImages?.add(key)
  hook.pushEvent("product_image_persisted", {id: Number(productId), date_create: dateCreate})
}

function posDraftKey(element) {
  const user = element.querySelector(".session-store-status")?.textContent?.trim() || "default"
  return `${POS_DRAFT_KEY_PREFIX}:${user}`
}

function updateDiscountPreview(form) {
  const base = Number.parseFloat(form.dataset.discountBase) || 0
  const input = form.querySelector("#discount-input")
  const deduction = discountDeduction(form.dataset.discountType, input?.value, base)
  const values = form.querySelectorAll(".discount-preview dd")
  if (values[0]) values[0].textContent = money(base)
  if (values[1]) values[1].textContent = `−${money(deduction)}`
  if (values[2]) values[2].textContent = money(base - deduction)
}

function discountDeduction(type, entered, base) {
  if (entered === null || entered === undefined || String(entered).trim() === "") return 0
  const bounded = Math.max(Number.parseFloat(entered) || 0, 0)
  if (type === "percent") return base * Math.min(bounded, 100) / 100
  if (type === "final_price") return Math.max(base - Math.min(bounded, base), 0)
  return Math.min(bounded, base)
}

function discountInputForType(type, deduction, base) {
  if (type === "percent") return base > 0 ? String((deduction / base * 100).toFixed(2)) : ""
  if (type === "final_price") return String(Math.max(base - deduction, 0).toFixed(2))
  return String(Math.max(deduction, 0).toFixed(2))
}

function discountInputLabel(type) {
  if (type === "percent") return t("pos.discount.percentage")
  if (type === "final_price") return t("pos.discount.finalPrice")
  return t("pos.discount.amount")
}

function discountInputHelp(type, lineLevel) {
  if (type === "percent") return t("pos.discount.percentHelp")
  if (type === "final_price") return lineLevel ? t("pos.discount.finalPriceLineHelp") : t("pos.discount.finalPriceOrderHelp")
  return lineLevel ? t("pos.discount.amountHelp") : t("pos.discount.orderAmountHelp")
}

function calculateCart(panel) {
  const number = value => Number.parseFloat(value) || 0
  const lines = [...panel.querySelectorAll(".cart-line")].map(element => {
    const price = number(element.dataset.price)
    const quantity = Math.max(0, number(element.querySelector(".quantity-input")?.value))
    const discount = number(element.dataset.discount)
    const discountType = element.dataset.discountType
    const gross = price * quantity
    const lineDiscount = discountType === "percent" ? gross * Math.min(discount, 100) / 100 : Math.min(discount, gross)
    return {element, price, quantity, sub: number(element.dataset.sub), tax: number(element.dataset.tax), gross, lineDiscount}
  })
  const grossSubtotal = lines.reduce((sum, line) => sum + line.gross, 0)
  const lineDiscountTotal = lines.reduce((sum, line) => sum + line.lineDiscount, 0)
  const beforeOrderDiscount = grossSubtotal - lineDiscountTotal
  const orderDiscountInput = number(panel.dataset.orderDiscount)
  const orderDiscount = panel.dataset.orderDiscountType === "percent"
    ? beforeOrderDiscount * Math.min(orderDiscountInput, 100) / 100
    : Math.min(orderDiscountInput, beforeOrderDiscount)
  const delivery = number(panel.dataset.delivery)
  const merchandiseTotal = beforeOrderDiscount - orderDiscount
  const total = merchandiseTotal + delivery
  const orderFactor = beforeOrderDiscount ? merchandiseTotal / beforeOrderDiscount : 1
  let subtotal = 0
  let tax = 0
  lines.forEach(line => {
    const lineFactor = line.gross ? (line.gross - line.lineDiscount) / line.gross : 1
    subtotal += line.sub * line.quantity * lineFactor * orderFactor
    tax += line.tax * line.quantity * lineFactor * orderFactor
    const values = line.element.querySelectorAll(".cart-line-breakdown strong")
    values[0] && (values[0].textContent = money(line.sub * lineFactor))
    values[1] && (values[1].textContent = money(line.tax * lineFactor))
    values[2] && (values[2].textContent = money(line.price * lineFactor))
    const lineTotal = line.element.querySelector(".cart-line-total")
    if (lineTotal) lineTotal.textContent = money(line.gross - line.lineDiscount)
  })
  const rows = panel.querySelectorAll(".totals > div")
  if (rows[0]) rows[0].querySelector("dd").textContent = String(lines.reduce((sum, line) => sum + line.quantity, 0))
  if (rows[1]) rows[1].querySelector("dd").textContent = money(subtotal)
  if (rows[2]) rows[2].querySelector("dd").textContent = money(tax)
  if (rows[3]) rows[3].querySelector("dd").textContent = `−${money(lineDiscountTotal + orderDiscount)}`
  const grandTotal = panel.querySelector(".grand-total dd")
  if (grandTotal) grandTotal.textContent = money(total)

  const checkoutTotal = document.querySelector("#checkout-total")
  if (checkoutTotal) checkoutTotal.textContent = money(total)

  const paymentLines = document.querySelector("#payment-lines")
  if (paymentLines) paymentLines.dataset.saleTotal = String(total)
  window.dispatchEvent(new CustomEvent("pos:checkout-total", {detail: {total}}))
}

function dialogHook() {
  return {
    mounted() {
      this.el.showModal()
      this.el.addEventListener("cancel", event => event.preventDefault())
      this.el.addEventListener("click", event => { if (event.target === this.el) event.preventDefault() })
    }
  }
}

function productDialogHook() {
  return {
    mounted() {
      this.el.showModal()
      this.el.addEventListener("cancel", event => event.preventDefault())
      this.el.addEventListener("keydown", event => {
        if (event.key !== "Escape") return
        event.preventDefault()
        event.stopPropagation()
      }, true)
      this.el.addEventListener("click", event => { if (event.target === this.el) event.preventDefault() })
    }
  }
}

function purchaseOrderLinesHook() {
  return {
    mounted() { initializePurchaseOrderLines(this) },
    updated() {
      initializePurchaseOrderLines(this)
      translatePage(this.el)
      if (!this.focusNewLine) return
      this.focusNewLine = false
      this.el.querySelector("[data-order-line]:last-child [role='combobox']")?.focus()
    }
  }
}

function purchaseOrdersHook() {
  return {
    mounted() {
      this.onObservedKeydown = event => {
        if (!event.target.matches("[data-observed-input], .observed-input")) return
        if (!["Enter", "ArrowDown", "ArrowUp"].includes(event.key)) return
        event.preventDefault()
        event.stopImmediatePropagation()
        const inputs = [...this.el.querySelectorAll("[data-observed-input], .observed-input")].filter(input => !input.disabled)
        const index = inputs.indexOf(event.target)
        const next = inputs[Math.max(0, Math.min(inputs.length - 1, index + (event.key === "ArrowUp" ? -1 : 1)))]
        next?.scrollIntoView({block: "center", behavior: "smooth"})
        next?.focus({preventScroll: true})
      }
      this.el.addEventListener("keydown", this.onObservedKeydown, true)
      this.onProcessOrder = event => {
        const button = event.target.closest("button[form='receive-order-form']")
        if (!button) return
        event.preventDefault()
        event.stopImmediatePropagation()
        button.disabled = true
        const observed = Object.fromEntries([...this.el.querySelectorAll("[name^='observed']")].map(input => [input.name.match(/\[(.+)\]/)?.[1], input.value]).filter(([id]) => id))
        this.pushEvent("receive_order", {observed})
      }
      this.el.addEventListener("click", this.onProcessOrder, true)
    },
    updated() { translatePage(this.el) },
    destroyed() { this.el.removeEventListener("keydown", this.onObservedKeydown, true); this.el.removeEventListener("click", this.onProcessOrder, true) }
  }
}

function initializePurchaseOrderLines(hook) {
  hook.boundLines ||= new WeakSet()
  const form = hook.el.closest("form")
  if (form && !form.dataset.purchaseOrderComboboxGuard) {
    form.dataset.purchaseOrderComboboxGuard = "true"
    form.addEventListener("keydown", event => {
      if (event.key === "Enter" && event.target.matches("[role='combobox']")) event.preventDefault()
    }, true)
    form.addEventListener("submit", event => {
      if (form.dataset.comboboxSelecting !== "true") return
      event.preventDefault()
      event.stopImmediatePropagation()
    }, true)
  }
  hook.el.querySelectorAll("[data-order-line]").forEach(line => {
    if (hook.boundLines.has(line)) return
    hook.boundLines.add(line)
    const input = line.querySelector("[role='combobox']")
    const list = line.querySelector("[role='listbox']")
    const options = () => [...list.querySelectorAll("[role='option']")]
    let matches = [], active = -1
    const render = () => {
      const query = input.value.trim().toLowerCase()
      matches = options().filter(option => `${option.dataset.productName} ${option.dataset.productCode}`.toLowerCase().includes(query)).slice(0, 50)
      options().forEach(option => { option.hidden = !matches.includes(option); option.setAttribute("aria-selected", String(matches[active] === option)) })
      list.hidden = matches.length === 0
      input.setAttribute("aria-expanded", String(matches.length > 0))
      input.setAttribute("aria-activedescendant", active >= 0 ? matches[active]?.id || "" : "")
    }
    const close = () => { active = -1; list.hidden = true; input.setAttribute("aria-expanded", "false") }
    const choose = option => {
      if (!option) return
      form && (form.dataset.comboboxSelecting = "true")
      window.setTimeout(() => { if (form) delete form.dataset.comboboxSelecting }, 300)
      input.value = option.dataset.productCode ? `${option.dataset.productName} · ${option.dataset.productCode}` : option.dataset.productName
      close()
      hook.pushEvent("line_product", {id: line.dataset.lineId, product_id: option.dataset.productId})
      line.querySelector("[name^='quantity']")?.focus()
    }
    input.addEventListener("input", () => { active = -1; render() })
    input.addEventListener("focus", render)
    input.addEventListener("keydown", event => {
      if (["ArrowDown", "ArrowUp"].includes(event.key)) { event.preventDefault(); render(); active = event.key === "ArrowUp" && active < 0 ? matches.length - 1 : Math.max(0, Math.min(matches.length - 1, active + (event.key === "ArrowDown" ? 1 : -1))); render() }
      else if (event.key === "Home" && matches.length) { event.preventDefault(); active = 0; render() }
      else if (event.key === "End" && matches.length) { event.preventDefault(); active = matches.length - 1; render() }
      else if (event.key === "Enter" && matches.length) { event.preventDefault(); choose(matches[Math.max(active, 0)]) }
      else if (event.key === "Escape") close()
    })
    input.addEventListener("blur", () => setTimeout(close, 120))
    options().forEach(option => option.addEventListener("pointerdown", event => { event.preventDefault(); event.stopPropagation(); choose(option) }))
    const quantity = line.querySelector("[name^='quantity']")
    quantity?.addEventListener("keydown", event => {
      if (event.key !== "Enter") return
      event.preventDefault()
      if (line.querySelector("[phx-click='edit_line_product']")?.disabled || !quantity.validity.valid) return
      hook.focusNewLine = true
      hook.pushEvent("add_line", {})
    })
  })
}

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
