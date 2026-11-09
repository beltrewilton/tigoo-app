import "./sidebar-tooltips.js";
import * as printer from "./printer.js";
import { createPrintRelay } from "./print-relay.js";
import { uuid } from "./uuid.js";
import Pica from "../vendor/pica/pica.mjs";
import { API_BASE_URL, activeProducts, addSalePayment, adjustInventory, cancelSale, clearSession, companySettings, createCustomer, createPriceList, createProduct, createProductOrder, createProvider, createSale, createSequenceSet, createStore, createTauriGoogleAttempt, createUser, customerDetail, customerPurchases, customers, deactivateUser, deletePriceList, deleteProvider, deleteSequenceSet, deleteStore, exchangeTauriGoogleCode, inventoryQuantities, inventoryStoreQuantities, inventorySummary, login, moveInventory, pricingLists, product, productOrders, productTraces, purchaseSources, receiveProductOrder, saleDetails, salesReport, saveSession, session, setProductPrices, stores, tauriGoogleAuthorizationUrl, updatePriceList, updateProduct, updateProvider, updateSequenceSet, updateStore, updateUser, userOptions, users } from "./api.js";
import { createPos } from "./pos.js";
import { buildPaymentReceiptData, buildReceiptData } from "./receipt.js";
import { formatCurrency, getLanguage, onLanguageChange, setLanguage, t, translateDocument } from "./i18n.js";
import { createLanguageSwitcher } from "./language-switcher.js";
import { initializeThemePicker } from "./theme.js";

const printerStatus = document.querySelector("#printer-status");
const printButton = document.querySelector("#print-test");
const printStatus = document.querySelector("#print-status");
const checkoutFlow = document.querySelector("#checkout-flow");
const checkoutStatus = document.querySelector("#checkout-status");
document.querySelector("#complete-sale").dataset.variant = "success";
const catalogPanel = document.querySelector(".catalog-panel");
const appShell = document.querySelector("#app-shell");
const startCheckoutButton = document.querySelector("#start-checkout");
const productGrid = document.querySelector("#product-grid");
const productStatus = document.querySelector("#products-status");
const productSearch = document.querySelector("#product-search");
const productSentinel = document.querySelector("#products-sentinel");
const customersScreen = document.querySelector("#customers-screen");
const customersFixed = customersScreen.querySelector(".invoice-report-fixed");
const customersTableBody = document.querySelector("#customers-table-body");
const customersStatus = document.querySelector("#customers-status");
const customerDetailPanel = document.querySelector("#customer-detail");
const customerDetailScreen = document.querySelector("#customer-detail-screen");
const customersBackButton = document.querySelector("#customers-back");
const customerSearch = document.querySelector("#customer-search");
const customerDialog = document.querySelector("#customer-dialog");
const customerForm = document.querySelector("#customer-form");
const customerFormStatus = document.querySelector("#customer-form-status");
const invoiceReport = document.querySelector("#invoice-report");
const invoiceReportFixed = document.querySelector(".invoice-report-fixed");
const invoiceTableBody = document.querySelector("#invoice-table-body");
const invoiceReportStatus = document.querySelector("#invoice-report-status");
const invoiceSearch = document.querySelector("#invoice-search");
const invoiceSentinel = document.querySelector("#invoice-sentinel");
const invoiceFilters = document.querySelector("#invoice-filters");
const invoiceDateFrom = document.querySelector("#invoice-date-from");
const invoiceDateTo = document.querySelector("#invoice-date-to");
const invoiceDateRangeTrigger = document.querySelector("#invoice-date-range-trigger");
const invoiceDateRangeDialog = document.querySelector("#invoice-date-range-dialog");
const invoiceCalendarGrid = document.querySelector("#invoice-calendar-grid");
const invoiceCancelDialog = document.querySelector("#invoice-cancel-dialog");
const orderTitle = document.querySelector("#order-title");
const clearCustomerButton = document.querySelector("#clear-customer");
const customerPurchasesButton = document.querySelector("#customer-purchases");
const customerPurchasesTitle = document.querySelector("#customer-purchases-title");
const customerPurchasesStatus = document.querySelector("#customer-purchases-status");
const customerPurchasesBody = document.querySelector("#customer-purchases-body");
const orderPanel = document.querySelector("#order-panel");
const mobileCartTrigger = document.querySelector("#mobile-cart-trigger");
const mobileCartNav = document.querySelector("#mobile-cart-nav");
const mobileTopbarCart = document.querySelector("#mobile-topbar-cart");
const mobileCartCount = document.querySelector("#mobile-cart-count");
const mobileCartClose = document.querySelector("#mobile-cart-close");
const mobileCartBackdrop = document.querySelector("#mobile-cart-backdrop");
const productSearchClear = document.querySelector("#product-search-clear");
const mobileNavigation = document.querySelector("#mobile-navigation");
const mobileNavigationClose = document.querySelector("#mobile-navigation-close");
let mobileNavigationTrigger = null;
let mobileNavigationRestoreFocus = true;
const languageSwitcher = createLanguageSwitcher(document.querySelector("#language-switcher"));
const userMenus = document.querySelectorAll(".user-menu");
const sidebarStoreMenu = document.querySelector("#sidebar-store");
initializeThemePicker(document.querySelector("#sidebar-theme"));
const sessionStoreStatus = document.querySelector("#session-store-status");
const POS_STORE_KEY = "pos-selected-store-id";
let storeId = null;
let availableStores = [];
let inventorySocket = null;
const imageResizer = new Pica();
const MAX_PRODUCT_IMAGE_BYTES = 10 * 1024 * 1024;
document.querySelector('[data-inventory-sort="quantity"]').textContent = t("ui.currentQuantity");
document.querySelector('[data-inventory-sort="prev_quantity"]').textContent = t("ui.previousQuantity");
const inventoryHeaderRow = document.querySelector("#inventory-screen .operations-table thead .table-row");
inventoryHeaderRow.lastElementChild.remove();
const totalQuantityHeader = document.createElement("th");
totalQuantityHeader.className = "table-head";
totalQuantityHeader.scope = "col";
totalQuantityHeader.textContent = t("ui.totalQuantity");
inventoryHeaderRow.children[5].before(totalQuantityHeader);
const pos = createPos({
  cartElement: document.querySelector("#cart"),
  totalTrigger: document.querySelector("#grand-total"),
  totalElement: document.querySelector("#total"),
  totalBeforeDiscountElement: document.querySelector("#total-before-discount"),
  subtotalElement: document.querySelector("#subtotal"),
  discountElement: document.querySelector("#discount"),
  taxElement: document.querySelector("#tax"),
  itemCountElement: document.querySelector("#items-count"),
  itemCountBadges: [mobileCartCount, document.querySelector("#sidebar-cart-count")],
  emptyElement: document.querySelector("#cart-empty"),
  clearButton: document.querySelector("#clear-order"),
  chargeButton: document.querySelector("#print-test"),
  checkoutButton: startCheckoutButton,
  productGrid,
  discountDialog: document.querySelector("#discount-dialog"),
  discountForm: document.querySelector("#discount-form"),
  discountTypeButtons: document.querySelectorAll("[data-discount-type]"),
  discountInput: document.querySelector("#discount-input"),
  discountInputLabel: document.querySelector("#discount-input-label"),
  discountHelp: document.querySelector("#discount-help"),
  discountProductImage: document.querySelector("#discount-product-image"),
  discountProductName: document.querySelector("#discount-product-name"),
  discountPreviewAmount: document.querySelector("#discount-preview-amount"),
  discountPreviewDiscount: document.querySelector("#discount-preview-discount"),
  discountPreviewTotal: document.querySelector("#discount-preview-total"),
  clearDialog: document.querySelector("#clear-order-dialog"),
  clearConfirmButton: document.querySelector("#confirm-clear-order"),
  t,
  formatCurrency,
});

let cursor = null;
let hasMore = true;
let loading = false;
let products = [];
let checkoutStage = "customer";
let checkoutOpening = false;
let selectedCustomer = null;
let customerSearchTimer;
let completedReceipt = null;
let printTargets = [];
let printRelay = null;
const printedRelayRequests = new Set();
let pendingPrintTimeout = null;
let printerAvailabilityTimer = null;
let invoiceCursor = null;
let invoiceHasMore = true;
let invoiceLoading = false;
let invoiceLoadError = false;
let invoices = [];
let invoiceSearchTimer;
let invoicePendingCancellation = null;
let calendarMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
let calendarRange = { from: "", to: "" };
let invoiceStatusFilter = "";
let expandedInvoiceId = null;
const invoiceDetails = new Map();
let invoiceSort = { key: "date_create", direction: "desc" };
let invoicesStale = false;
const inventoryScreen = document.querySelector("#inventory-screen");
const ordersScreen = document.querySelector("#orders-screen");
const purchaseOrderScreen = document.querySelector("#purchase-order-screen");
const companySettingsScreen = document.querySelector("#company-settings-screen");
const companySettingsCompany = document.querySelector("#company-settings-company");
const companySettingsStatus = document.querySelector("#company-settings-status");
const priceListsContent = document.querySelector("#price-lists-content");
const storesContent = document.querySelector("#stores-content");
const sequenceSetsContent = document.querySelector("#sequence-sets-content");
const providersContent = document.querySelector("#providers-content");
const inventoryTableBody = document.querySelector("#inventory-table-body");
const ordersTableBody = document.querySelector("#orders-table-body");
const inventorySearchInput = document.querySelector("#inventory-search");
const inventoryStatus = document.querySelector("#inventory-status");
const inventorySummaryGrid = document.querySelector("#inventory-summary");
const ordersStatus = document.querySelector("#orders-status");
const ordersSummary = document.querySelector("#orders-summary");
let inventoryEntries = [], purchaseOrders = [], purchaseOrderSources = [], purchaseOrderStatusCounts = {}, selectedOrder = null;
let orderCreateMode = "purchase";
let editingInventoryProductId = null;
let expandedInventoryDetail = null;
let expandedStoreQuantities = [];
let loadingStoreQuantitiesProductId = null;
let expandedProductTraces = [];
let loadingTraceProductId = null;
let inventorySort = { key: "last_update", direction: "desc" };
let inventoryFilter = "";
let pendingProductSelection = null;
let pendingProductRefresh = null;
let createdProduct = null;
let editingProductId = null;
let preparedProductImage = null;
let imagePreparationTask = null;
let selectedProductImageFile = null;
let preparedStoreLogo = null;
let storeLogoPreparationTask = null;
let selectedStoreLogoFile = null;
let purchaseOrderSort = { key: "last_updated", direction: "desc" };
let purchaseOrderStatusFilter = "";
let companySettingsData = { company: null, price_lists: [], stores: [], sequence_sets: [], providers: [] };
let editingCompanySetting = null;

const mobileQuery = window.matchMedia("(max-width: 640px)");

// The catalog panel is the scroll surface on mobile.  Keeping the gesture here
// lets every list share the same WebView-friendly touch behavior without
// changing desktop scrolling or adding document-level touch handlers.
function createMobilePullToRefresh({ screen, onRefresh, isActive = () => !screen.hidden, scrollContainer = catalogPanel }) {
  const indicator = document.createElement("div");
  indicator.className = "mobile-pull-to-refresh";
  indicator.setAttribute("role", "status");
  indicator.setAttribute("aria-live", "polite");
  indicator.setAttribute("aria-label", "Pull down to refresh");
  indicator.innerHTML = '<span class="mobile-pull-to-refresh-icon" aria-hidden="true">↻</span>';
  screen.prepend(indicator);

  const threshold = 72;
  let startY = 0;
  let startX = 0;
  let distance = 0;
  let tracking = false;
  let vertical = false;
  let refreshing = false;

  const reset = () => {
    distance = 0;
    tracking = false;
    vertical = false;
    indicator.style.removeProperty("--mobile-pull-distance");
    indicator.classList.remove("is-pulling", "is-ready");
  };
  const isInteractive = (target) => target.closest("button, input, select, textarea, a, summary, [role='button'], [data-no-pull-refresh]");

  catalogPanel.addEventListener("touchstart", (event) => {
    if (!mobileQuery.matches || refreshing || !isActive() || scrollContainer.scrollTop > 0 || isInteractive(event.target)) return;
    const touch = event.touches[0];
    startY = touch.clientY;
    startX = touch.clientX;
    tracking = true;
    vertical = false;
  }, { passive: true });

  catalogPanel.addEventListener("touchmove", (event) => {
    if (!tracking || refreshing || !isActive()) return;
    const touch = event.touches[0];
    const deltaY = touch.clientY - startY;
    const deltaX = touch.clientX - startX;
    if (!vertical) {
      if (Math.abs(deltaX) > Math.abs(deltaY)) { tracking = false; return; }
      if (deltaY <= 0) return;
      vertical = true;
    }
    if (scrollContainer.scrollTop > 0 || deltaY <= 0) { reset(); return; }
    distance = Math.min(threshold * 1.35, deltaY * 0.48);
    indicator.style.setProperty("--mobile-pull-distance", `${distance}px`);
    indicator.classList.add("is-pulling");
    indicator.classList.toggle("is-ready", distance >= threshold);
    // Only take over once this is confirmed as a downward, top-of-list pull.
    event.preventDefault();
  }, { passive: false });

  const finish = async () => {
    if (!tracking) return;
    const shouldRefresh = distance >= threshold && !refreshing;
    reset();
    if (!shouldRefresh) return;
    refreshing = true;
    indicator.classList.add("is-refreshing");
    indicator.setAttribute("aria-label", "Refreshing");
    try {
      await onRefresh();
    } finally {
      refreshing = false;
      indicator.classList.remove("is-refreshing");
      indicator.setAttribute("aria-label", "Pull down to refresh");
    }
  };
  catalogPanel.addEventListener("touchend", finish, { passive: true });
  catalogPanel.addEventListener("touchcancel", reset, { passive: true });
}

function populateStoreOptions() {
  document.querySelectorAll("#inventory-store, #inventory-form-store, #order-destination").forEach((select) => {
    const selected = String(storeId);
    select.replaceChildren(...availableStores.map((store) => {
      const option = document.createElement("option"); option.value = store.id; option.textContent = store.name; return option;
    }));
    select.value = selected;
  });
  const storeMenuContent = sidebarStoreMenu.querySelector(".sidebar-menu-content");
  storeMenuContent.replaceChildren(...availableStores.map((store) => {
    const button = document.createElement("button"); button.type = "button"; button.className = "sidebar-menu-action"; button.dataset.storeId = store.id; button.textContent = store.name; button.setAttribute("aria-current", String(Number(store.id) === Number(storeId))); return button;
  }));
}

function selectedStore() { return availableStores.find((store) => Number(store.id) === Number(storeId)); }

function updateStoreTitles() {
  const storeName = selectedStore()?.name;
  const titleKeys = { "pos-title": "pos.title", "invoice-report-title": "ui.invoiceReport" };
  document.querySelectorAll("#pos-title, #invoice-report-title, #inventory-title, #orders-title, #purchase-order-title, #company-settings-title, #checkout-title").forEach((element) => {
    const title = titleKeys[element.id] ? t(titleKeys[element.id]) : element.dataset.storeTitleBase;
    if (!element.dataset.storeTitleBase) element.dataset.storeTitleBase = title || element.textContent.trim();
    element.textContent = storeName ? `${title || element.dataset.storeTitleBase} — ${storeName}` : (title || element.dataset.storeTitleBase);
  });
}

function updateSessionStore() {
  const current = session();
  if (!current || !storeId) return;
  saveSession({ ...current, store_id: Number(storeId) });
  try { localStorage.setItem(POS_STORE_KEY, String(storeId)); } catch {}
}

function updateSessionStoreDisplay() {
  const { login } = currentUserIdentity();
  sessionStoreStatus.textContent = login;
}

async function selectStore(nextStoreId) {
  const next = availableStores.find((store) => Number(store.id) === Number(nextStoreId));
  if (!next || Number(next.id) === Number(storeId)) return;
  inventorySocket?.close();
  storeId = next.id;
  updateSessionStore();
  populateStoreOptions();
  updateSessionStoreDisplay();
  updateStoreTitles();
  products = [];
  cursor = null;
  hasMore = true;
  inventoryEntries = [];
  purchaseOrders = [];
  selectedOrder = null;
  editingInventoryProductId = null;
  expandedInventoryDetail = null;
  expandedStoreQuantities = [];
  expandedProductTraces = [];
  loadingTraceProductId = null;
  pos.clear();
  subscribeToInventory();
  await loadProducts();
  if (!inventoryScreen.hidden) await loadInventory();
  if (!ordersScreen.hidden) await loadOrders();
}

async function initializeStores() {
  const { entries } = await stores();
  availableStores = entries;
  let savedStoreId = null;
  try { savedStoreId = localStorage.getItem(POS_STORE_KEY); } catch {}
  storeId = entries.find((store) => Number(store.id) === Number(savedStoreId))?.id
    || entries.find((store) => Number(store.id) === Number(session()?.store_id))?.id
    || null;
  updateSessionStore();
  populateStoreOptions();
  if (!storeId) throw new Error(t("ui.selectStoreContinue"));
  updateSessionStoreDisplay();
  updateStoreTitles();
  subscribeToInventory();
  startPrintRelay();
  companySettings().then((data) => { companySettingsData = data; renderSequenceOptions(); }).catch(() => {});
  loadProducts();
}

function navigationIcon() {
  return `<svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h16"/></svg>`;
}

function closeMobileNavigation({ restoreFocus = true } = {}) {
  mobileNavigationRestoreFocus = restoreFocus;
  if (mobileNavigation.open) mobileNavigation.close();
}

function openMobileNavigation(trigger) {
  if (!mobileQuery.matches || mobileNavigation.open) return;
  mobileNavigationTrigger = trigger;
  trigger.setAttribute("aria-expanded", "true");
  mobileNavigation.showModal();
}

function addMobileNavigationTrigger(topbar) {
  if (topbar.querySelector(".mobile-navigation-trigger")) return;
  const trigger = document.createElement("button");
  trigger.className = "btn mobile-navigation-trigger";
  trigger.type = "button";
  trigger.dataset.variant = "ghost";
  trigger.dataset.size = "icon";
  trigger.setAttribute("aria-label", t("ui.openNavigation"));
  trigger.setAttribute("aria-controls", "mobile-navigation");
  trigger.setAttribute("aria-expanded", "false");
  trigger.innerHTML = navigationIcon();
  trigger.addEventListener("click", () => openMobileNavigation(trigger));
  topbar.prepend(trigger);
}
document.querySelectorAll(".topbar").forEach(addMobileNavigationTrigger);

mobileTopbarCart.addEventListener("click", () => setMobileCart(true));

mobileNavigationClose.addEventListener("click", () => closeMobileNavigation());
mobileNavigation.addEventListener("click", (event) => {
  if (event.target === mobileNavigation) closeMobileNavigation();
});
mobileNavigation.addEventListener("close", () => {
  mobileNavigationTrigger?.setAttribute("aria-expanded", "false");
  if (mobileNavigationRestoreFocus) mobileNavigationTrigger?.focus();
  mobileNavigationRestoreFocus = true;
});

document.querySelectorAll("[data-mobile-language]").forEach((button) => {
  button.addEventListener("click", () => {
    setLanguage(button.dataset.mobileLanguage);
    document.querySelector("#mobile-language-switcher").open = false;
  });
});
function syncMobileLanguageOptions() {
  document.querySelectorAll("[data-mobile-language]").forEach((button) => {
    button.setAttribute("aria-current", String(button.dataset.mobileLanguage === getLanguage()));
  });
}
syncMobileLanguageOptions();
onLanguageChange(syncMobileLanguageOptions);

function setMobileCart(open, { restoreFocus = true } = {}) {
  if (!mobileQuery.matches) return;
  orderPanel.classList.toggle("is-mobile-open", open);
  mobileCartBackdrop.classList.toggle("is-visible", open);
  [mobileCartTrigger, mobileCartNav, mobileTopbarCart].forEach((trigger) => trigger.setAttribute("aria-expanded", String(open)));
  if (open) {
    orderPanel.setAttribute("role", "dialog");
    orderPanel.setAttribute("aria-modal", "true");
  } else {
    orderPanel.removeAttribute("role");
    orderPanel.removeAttribute("aria-modal");
  }
  catalogPanel.toggleAttribute("inert", open);
  if (open) requestAnimationFrame(() => mobileCartClose.focus());
  else if (restoreFocus) mobileCartNav.focus();
}
mobileCartTrigger.addEventListener("click", () => setMobileCart(true));
mobileCartNav.addEventListener("click", () => setMobileCart(true));
mobileCartClose.addEventListener("click", () => setMobileCart(false));
mobileCartBackdrop.addEventListener("click", () => setMobileCart(false));
document.addEventListener("keydown", (event) => { if (event.key === "Escape" && orderPanel.classList.contains("is-mobile-open")) setMobileCart(false); });
mobileQuery.addEventListener("change", () => {
  if (!mobileQuery.matches) closeMobileNavigation({ restoreFocus: false });
  if (mobileQuery.matches) return;
  orderPanel.classList.remove("is-mobile-open");
  mobileCartBackdrop.classList.remove("is-visible");
  [mobileCartTrigger, mobileCartNav, mobileTopbarCart].forEach((trigger) => trigger.setAttribute("aria-expanded", "false"));
  orderPanel.removeAttribute("role");
  orderPanel.removeAttribute("aria-modal");
  catalogPanel.removeAttribute("inert");
});

function updateInvoiceStickyOffset() {
  invoiceReport.style.setProperty("--invoice-fixed-height", `${invoiceReportFixed.offsetHeight}px`);
}

new ResizeObserver(updateInvoiceStickyOffset).observe(invoiceReportFixed);
function updateCustomersStickyOffset() {
  customersScreen.style.setProperty("--customers-fixed-height", `${customersFixed.offsetHeight}px`);
}

new ResizeObserver(updateCustomersStickyOffset).observe(customersFixed);
document.querySelectorAll(".operations-fixed").forEach((fixed) => new ResizeObserver(() => fixed.closest(".operations-screen").style.setProperty("--operations-fixed-height", `${fixed.offsetHeight}px`)).observe(fixed));

function updateCustomerPicker() {
  orderTitle.textContent = selectedCustomer?.name || t("customer.pick");
  orderTitle.title = selectedCustomer?.name || "";
  orderTitle.setAttribute("aria-label", selectedCustomer ? t("customer.change") : t("customer.pick"));
  clearCustomerButton.hidden = !selectedCustomer;
  customerPurchasesButton.disabled = false;
}

function purchaseRows(purchase) {
  const row = document.createElement("tr");
  row.className = "table-row";
  const date = purchase.date_create ? new Date(purchase.date_create.replace(" ", "T")).toLocaleString() : "—";
  [[date, ""], [purchase.salesperson || "", ""], [null, ""], [purchase.invoice_status || purchase.status || "—", ""], [currency(purchase.amount), "numeric"]].forEach(([value, className], index) => {
    const cell = document.createElement("td");
    cell.className = `table-cell ${className}`.trim();
    if (index === 2) {
      const trigger = document.createElement("button");
      const detailsId = `customer-purchase-items-${purchase.id}`;
      trigger.className = "btn customer-purchase-detail-trigger";
      trigger.type = "button";
      trigger.dataset.variant = "ghost";
      trigger.setAttribute("aria-expanded", "false");
      trigger.setAttribute("aria-controls", detailsId);
      const disclosure = document.createElement("span");
      disclosure.className = "customer-purchase-disclosure";
      disclosure.setAttribute("aria-hidden", "true");
      disclosure.textContent = "▸";
      trigger.append(disclosure, document.createTextNode(`Items (${purchase.items.length})`));
      cell.appendChild(trigger);
    } else {
      cell.textContent = value || "—";
    }
    row.appendChild(cell);
  });

  const detailsRow = document.createElement("tr");
  detailsRow.id = `customer-purchase-items-${purchase.id}`;
  detailsRow.className = "table-row customer-purchase-details-row";
  detailsRow.hidden = true;
  const detailsCell = document.createElement("td");
  detailsCell.className = "table-cell";
  detailsCell.colSpan = 5;
  const table = document.createElement("table");
  table.className = "table customer-purchase-items-table";
  const caption = document.createElement("caption");
  caption.className = "sr-only";
  caption.textContent = `Items on ${purchase.sequence || `sale ${purchase.id}`}`;
  const head = document.createElement("thead");
  const headRow = document.createElement("tr");
  headRow.className = "table-row";
  ["Item", "Quantity", "Price", "Discount", "Total"].forEach((label) => {
    const header = document.createElement("th");
    header.className = "table-head";
    header.scope = "col";
    header.textContent = label;
    headRow.appendChild(header);
  });
  head.appendChild(headRow);
  const body = document.createElement("tbody");
  purchase.items.forEach((item) => {
    const itemRow = document.createElement("tr");
    itemRow.className = "table-row";
    [item.name || `Product #${item.product_id}`, item.quantity, currency(item.price), discountDisplay(item.discount, item.discount_type, item.discount_input), currency(item.total)].forEach((value, index) => {
      const itemCell = document.createElement("td");
      itemCell.className = index > 1 ? "table-cell numeric" : "table-cell";
      itemCell.textContent = value;
      itemRow.appendChild(itemCell);
    });
    body.appendChild(itemRow);
  });
  table.append(caption, head, body);
  detailsCell.appendChild(table);
  detailsRow.appendChild(detailsCell);
  row.querySelector(".customer-purchase-detail-trigger").addEventListener("click", (event) => {
    const expanded = event.currentTarget.getAttribute("aria-expanded") === "true";
    event.currentTarget.setAttribute("aria-expanded", String(!expanded));
    event.currentTarget.querySelector(".customer-purchase-disclosure").textContent = expanded ? "▸" : "▾";
    detailsRow.hidden = expanded;
  });

  return [row, detailsRow];
}

async function openCustomerPurchases() {
  if (!selectedCustomer) return;
  const customer = selectedCustomer;
  const dialog = document.querySelector("#customer-purchases-dialog");
  const requestId = uuid();
  dialog.dataset.purchaseRequestId = requestId;
  if (!dialog.open) dialog.showModal();
  customerPurchasesTitle.textContent = `${customer.name} — recent purchases`;
  customerPurchasesBody.replaceChildren(...purchaseHistorySkeletonRows());
  customerPurchasesStatus.hidden = false;
  customerPurchasesStatus.textContent = t("ui.loadingPurchases");

  try {
    const { entries } = await customerPurchases(customer.id);
    if (dialog.dataset.purchaseRequestId !== requestId) return;
    customerPurchasesBody.replaceChildren(...entries.flatMap(purchaseRows));
    customerPurchasesStatus.textContent = entries.length ? "" : t("ui.noPurchases");
  } catch (error) {
    console.error(error);
    if (dialog.dataset.purchaseRequestId !== requestId) return;
    customerPurchasesBody.replaceChildren();
    customerPurchasesStatus.textContent = t("ui.purchasesLoadError");
  }
}

function skeletonBlock(className = "", width = "100%") {
  const block = document.createElement("span");
  block.className = `skeleton ${className}`.trim();
  block.style.width = width;
  block.setAttribute("aria-hidden", "true");
  return block;
}

function purchaseHistorySkeletonRows() {
  return Array.from({ length: 4 }, () => {
    const row = document.createElement("tr");
    row.className = "table-row skeleton-table-row";
    ["72%", "64%", "56%", "58%", "46%"].forEach((width, index) => {
      const cell = document.createElement("td");
      cell.className = `table-cell${index === 4 ? " numeric" : ""}`;
      cell.appendChild(skeletonBlock("skeleton-line", width));
      row.appendChild(cell);
    });
    return row;
  });
}

// A completed sale starts a completely new order. Keep this in one place so no
// customer, payment, delivery, or invoice choice leaks into the next sale.
function resetCompletedOrder() {
  selectedCustomer = null;
  updateCustomerPicker();

  const choice = document.querySelector("#customer-picker");
  const details = document.querySelector("#customer-details");
  choice.textContent = t("customer.pick");
  details.hidden = true;
  details.textContent = "";
  document.querySelector("#customer-continue").disabled = true;

  const creditToggle = document.querySelector("#credit-toggle");
  creditToggle.setAttribute("aria-pressed", "false");
  creditToggle.dataset.variant = "outline";
  creditToggle.disabled = true;
  document.querySelector("#payment-inputs").hidden = false;
  document.querySelector("#payment-lines").replaceChildren();
  document.querySelector("#payment-balance").textContent = "";
  document.querySelector("#payment-change").hidden = true;
  document.querySelector("#payment-change").textContent = "";
  document.querySelector("#sale-additional-info").value = "";
  document.querySelector("#payment-choice").textContent = "—";

  const deliveryToggle = document.querySelector("#delivery-toggle");
  deliveryToggle.setAttribute("aria-pressed", "false");
  deliveryToggle.dataset.variant = "outline";
  document.querySelector("#delivery-options").hidden = true;
  document.querySelector("#delivery-options").replaceChildren();
  document.querySelector("#delivery-summary").hidden = true;
  document.querySelectorAll("[data-sequence]").forEach((button) => {
    button.dataset.variant = button.dataset.sequence === "CF" ? "default" : "secondary";
  });
  updateSequenceDescription();

  checkoutStatus.textContent = "";
  productSearch.value = "";
  productSearchClear.hidden = true;
  customerSearch.value = "";
  clearTimeout(customerSearchTimer);
  if (!customersScreen.hidden) loadCustomers();
  pos.clear();
  renderProducts();
}

function customerRow(customer, returnTo) {
  const row = document.createElement("tr");
  row.className = "table-row";
  const values = [["Name", customer.name || "—"], ["Document ID", customer.document_id || "—"], ["Phone", customer.celphone || "—"], ["Email", customer.email || "—"], ["Wholesale", Number(customer.wholesaler) === 1 ? "Yes" : "No"], ["Pending balance", currency(Math.max(Number(customer.pending_balance || 0), 0))], ["Last purchase", customer.last_purchase_date ? new Date(customer.last_purchase_date.replace(" ", "T")).toLocaleDateString() : "—"]];
  const visibleValues = returnTo === "standalone" ? values : values.slice(0, 3);
  visibleValues.forEach(([label, value]) => { const cell = document.createElement("td"); cell.className = "table-cell"; cell.dataset.label = label; cell.textContent = value; row.appendChild(cell); });
  const action = document.createElement("td"); action.className = "table-cell customer-action";
  const actionButton = document.createElement("button"); actionButton.className = "btn"; actionButton.type = "button"; actionButton.dataset.variant = "outline"; actionButton.dataset.size = "sm"; actionButton.dataset.customerId = customer.id;
  const standalone = returnTo === "standalone";
  const actionLabel = standalone ? t("ui.view") : t("customer.choose");
  actionButton.textContent = actionLabel; actionButton.setAttribute("aria-label", `${actionLabel}: ${customer.name || ""}`); action.appendChild(actionButton); row.appendChild(action);
  return row;
}

function customerDate(value) { const parts = dateTimeParts(value); return parts ? `${parts.date} ${parts.time}` : "—"; }
async function openCustomerDetail(id) {
  customerListScrollTop = catalogPanel.scrollTop;
  customersScreen.hidden = true;
  customerDetailScreen.hidden = false;
  catalogPanel.dataset.view = "customer-detail";
  catalogPanel.scrollTop = 0;
  customerDetailPanel.innerHTML = `<div class="card-content invoice-details-skeleton" role="status" aria-label="${t("ui.loadingDetails")}"><span class="skeleton skeleton-line" style="width:40%"></span><span class="skeleton skeleton-line" style="width:75%"></span></div>`;
  document.querySelector("#customer-detail-title").focus();
  try {
    const detail = await customerDetail(id), customer = detail.customer, summary = detail.summary;
    const purchases = detail.purchases.map((purchase) => `<tr class="table-row"><td class="table-cell">${purchase.sequence || `#${purchase.id}`}</td><td class="table-cell">${customerDate(purchase.date_create)}</td><td class="table-cell numeric">${currency(purchase.amount)}</td><td class="table-cell numeric">${currency(purchase.total_paid)}</td><td class="table-cell numeric">${currency(Math.max(Number(purchase.due_balance || 0), 0))}</td><td class="table-cell">${purchase.invoice_status || "—"}</td><td class="table-cell">${purchase.salesperson || "—"}</td><td class="table-cell">${purchase.store_id || "—"}</td><td class="table-cell"><button class="btn" type="button" data-variant="ghost" data-customer-invoice>${t("ui.view")}</button></td></tr>`).join("") || `<tr class="table-row"><td class="table-cell muted" colspan="9">${t("ui.noPurchases")}</td></tr>`;
    customerDetailPanel.innerHTML = `<div class="card-header"><div><p class="eyebrow">${t("ui.customerAccount")}</p><h3 class="card-title">${customer.name || t("detail.customerFallback")}</h3><p class="card-description">${customer.document_id || t("detail.noDocument")} · ${customer.celphone || t("detail.noPhone")}</p></div></div><div class="card-content"><p class="card-description">${customer.address || t("detail.noAddress")} · ${customer.email || t("detail.noEmail")} · ${Number(customer.wholesaler) === 1 ? t("ui.wholesale") : t("ui.retail")} · ${t("ui.created", { date: customerDate(customer.date_create) })}</p><section class="invoice-summary"><article class="card"><div class="card-header"><p class="card-title">${t("ui.pendingBalance")}</p></div><div class="card-content"><p class="invoice-kpi-value numeric">${currency(summary.pending_balance)}</p></div></article><article class="card"><div class="card-header"><p class="card-title">${t("ui.totalInvoiced")}</p></div><div class="card-content"><p class="invoice-kpi-value numeric">${currency(summary.total_invoiced)}</p></div></article><article class="card"><div class="card-header"><p class="card-title">${t("ui.totalPaid")}</p></div><div class="card-content"><p class="invoice-kpi-value numeric">${currency(summary.total_paid)}</p></div></article><article class="card"><div class="card-header"><p class="card-title">${t("ui.outstandingBalance")}</p></div><div class="card-content"><p class="invoice-kpi-value numeric">${currency(summary.pending_balance)}</p></div></article><article class="card"><div class="card-header"><p class="card-title">${t("ui.purchases")}</p></div><div class="card-content"><p class="invoice-kpi-value numeric">${summary.purchase_count}</p></div></article><article class="card"><div class="card-header"><p class="card-title">${t("ui.lastPurchase")}</p></div><div class="card-content"><p class="card-description">${customerDate(summary.last_purchase_date)}</p></div></article></section><div class="table-container"><p class="invoice-table-section-title">${t("ui.purchaseHistory")}</p><table class="table"><thead><tr class="table-row"><th class="table-head">${t("ui.invoice")}</th><th class="table-head">${t("ui.date")}</th><th class="table-head">${t("ui.total")}</th><th class="table-head">${t("ui.paid")}</th><th class="table-head">${t("ui.balance")}</th><th class="table-head">${t("ui.status")}</th><th class="table-head">${t("ui.salesPerson")}</th><th class="table-head">${t("ui.store")}</th><th class="table-head">${t("ui.action")}</th></tr></thead><tbody>${purchases}</tbody></table></div></div>`;
    customerDetailPanel.querySelectorAll("[data-customer-invoice]").forEach((button) => button.addEventListener("click", () => { invoiceSearch.value = customer.name || ""; openInvoiceReport(); loadInvoices({ reset: true }); }));
  } catch (error) { customerDetailPanel.textContent = error.message; }
}

async function loadCustomers() {
  const request = ++customerListRequest;
  const returnTo = customerReturn;
  const standalone = returnTo === "standalone";
  customersScreen.toggleAttribute("data-customer-picker", !standalone);
  document.querySelectorAll("[data-customer-management-column]").forEach((column) => { column.hidden = !standalone; });
  document.querySelector("#customers-action-heading").textContent = standalone ? t("ui.view") : t("customer.choose");
  customersStatus.textContent = t("customer.loading");
  customersTableBody.replaceChildren();
  try {
    const page = await customers(customerSearch.value.trim());
    if (request !== customerListRequest) return;
    customersTableBody.replaceChildren(...page.entries.map((customer) => customerRow(customer, returnTo)));
    if (!page.entries.length) customersStatus.textContent = t("customer.empty");
    else customersStatus.textContent = "";
    customersTableBody.querySelectorAll("[data-customer-id]").forEach((button) => {
      button.addEventListener("click", () => {
        const customer = page.entries.find((entry) => String(entry.id) === button.dataset.customerId);
        if (returnTo === "standalone") openCustomerDetail(button.dataset.customerId); else selectCustomer(customer);
      });
    });
  } catch (error) {
    if (request !== customerListRequest) return;
    console.error(error); customersStatus.textContent = t("customer.error");
  }
}

let customerReturn = "pos";
let customerListScrollTop = 0;
let customerListRequest = 0;
function openCustomers(returnTo = "pos") {
  closeUsersPage();
  customerReturn = returnTo;
  const standalone = returnTo === "standalone";
  invoiceReport.hidden = true;
  customerDetailScreen.hidden = true;
  closeOperations();
  checkoutFlow.hidden = true;
  catalogPanel.dataset.view = "customers";
  customersScreen.hidden = false;
  updateCustomersStickyOffset();
  customersBackButton.hidden = standalone;
  appShell.classList.toggle("invoice-view", standalone);
  if (standalone) selectSidebar("customers-nav");
  loadCustomers();
  requestAnimationFrame(() => (mobileQuery.matches ? customerSearch : document.querySelector("#customers-title")).focus());
}

function closeCustomers() {
  customersScreen.hidden = true;
  customerDetailScreen.hidden = true;
  customersBackButton.hidden = false;
  if (catalogPanel.dataset.view === "customers") delete catalogPanel.dataset.view;
  if (customerReturn === "standalone") { openPos(); document.querySelector("#customers-nav").focus(); return; }
  if (customerReturn === "checkout") { catalogPanel.dataset.view = "checkout"; checkoutFlow.hidden = false; showCheckoutStage("customer"); }
  else if (customerReturn === "cart") { setMobileCart(true); }
  else { selectSidebar("pos-nav"); (mobileQuery.matches ? mobileCartNav : orderTitle).focus(); }
}

function closeCustomerDetail() {
  customerDetailScreen.hidden = true;
  customersScreen.hidden = false;
  catalogPanel.dataset.view = "customers";
  requestAnimationFrame(() => {
    catalogPanel.scrollTop = customerListScrollTop;
    customersTableBody.querySelector(`[data-customer-id]`)?.focus();
  });
}

function currency(value) {
  return formatCurrency(value);
}

function discountDisplay(discount, type, input) {
  if (!Number(discount || 0)) return "-";
  return type === "percentage" && input != null ? `${Number(input)}%` : currency(discount);
}

function renderCurrencyPlaceholders() {
  document.querySelectorAll("[data-currency]").forEach((element) => {
    element.textContent = currency(element.dataset.currency);
  });
}

function dateValue(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function rangeLabel(from, to) {
  if (!from) return t("ui.anyDate");
  const format = (value) => new Date(`${value}T00:00:00`).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
  return to ? `${format(from)} – ${format(to)}` : format(from);
}

function renderCalendar() {
  document.querySelector("#calendar-month-label").textContent = calendarMonth.toLocaleDateString(undefined, { month: "long", year: "numeric" });
  document.querySelector("#invoice-date-range-description").textContent = calendarRange.from && !calendarRange.to ? t("ui.chooseEndDate") : t("ui.chooseDateRange");
  invoiceCalendarGrid.replaceChildren();
  const firstWeekday = calendarMonth.getDay();
  const daysInMonth = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() + 1, 0).getDate();
  for (let blank = 0; blank < firstWeekday; blank += 1) invoiceCalendarGrid.appendChild(document.createElement("span"));
  for (let day = 1; day <= daysInMonth; day += 1) {
    const date = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth(), day);
    const value = dateValue(date);
    const button = document.createElement("button");
    button.className = "btn calendar-day";
    button.type = "button";
    button.dataset.date = value;
    button.dataset.variant = "ghost";
    button.dataset.size = "icon-sm";
    button.setAttribute("role", "gridcell");
    button.setAttribute("aria-label", date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric", year: "numeric" }));
    button.setAttribute("aria-selected", String(value === calendarRange.from || value === calendarRange.to));
    if (calendarRange.from && calendarRange.to && value > calendarRange.from && value < calendarRange.to) button.dataset.range = "middle";
    if (value === dateValue(new Date())) button.dataset.today = "";
    button.textContent = day;
    invoiceCalendarGrid.appendChild(button);
  }
}

function openDateRangePicker() {
  calendarRange = { from: invoiceDateFrom.value, to: invoiceDateTo.value };
  const initial = calendarRange.from ? new Date(`${calendarRange.from}T00:00:00`) : new Date();
  calendarMonth = new Date(initial.getFullYear(), initial.getMonth(), 1);
  renderCalendar();
  invoiceDateRangeDialog.showModal();
}

function invoiceStatusLabel(status) {
  return status === "close" ? t("ui.paid") : status === "cancelled" ? t("ui.cancelled") : t("ui.pending");
}

function updateInvoiceSummary(summary) {
  if (!summary) return;

  [["paid", "paid"], ["pending", "pending"], ["cancelled", "cancelled"]].forEach(([name, key]) => {
    document.querySelector(`#invoice-${name}-count`).textContent = Number(summary[`${key}_count`] || 0);
    document.querySelector(`#invoice-${name}-total`).textContent = currency(summary[`${key}_total`]);
  });
}

function invoicePaymentForm(invoice) {
  const payment = document.createElement("form");
  payment.className = "invoice-payment";
  payment.dataset.invoiceId = invoice.id;
  const createMethodSelector = (row, label) => {
    const methods = document.createElement("div");
    methods.className = "invoice-payment-methods sequence-options";
    methods.setAttribute("role", "group");
    methods.setAttribute("aria-label", label);
    row.dataset.paymentType = "CASH";
  [["CASH", t("checkout.cash")], ["CC", t("checkout.card")]].forEach(([type, labelText]) => {
      const method = document.createElement("button");
      method.className = "btn"; method.type = "button"; method.dataset.paymentType = type;
      method.dataset.variant = type === "CASH" ? "default" : "secondary";
      method.setAttribute("aria-pressed", String(type === "CASH"));
      method.textContent = labelText;
      methods.appendChild(method);
    });
    return methods;
  };
  const createAmount = ({ id, value, readonly = false, label }) => {
    const amountWrap = document.createElement("div");
    amountWrap.className = "invoice-payment-amount";
    if (readonly) amountWrap.classList.add("invoice-payment-amount-formatted");
    const amountLabel = document.createElement("label");
    amountLabel.className = "label sr-only";
    amountLabel.htmlFor = id;
    amountLabel.textContent = label;
    const amount = document.createElement("input");
    amount.className = "input numeric";
    amount.id = id;
    amount.value = value;
    if (readonly) {
      amount.type = "text";
      amount.readOnly = true;
      amount.setAttribute("aria-label", label);
    } else {
      amount.type = "number"; amount.min = "0.01"; amount.max = invoice.due_balance; amount.step = "0.01"; amount.required = true;
      amount.name = "paymentAmount";
    }
    amountWrap.append(amountLabel, amount);
    return amountWrap;
  };
  const primary = document.createElement("div");
  primary.className = "invoice-payment-row";
  primary.append(
    createAmount({ id: `invoice-payment-${invoice.id}`, value: "0", label: t("ui.paymentAmount", { invoice: invoice.sequence || invoice.id }) }),
    createMethodSelector(primary, t("checkout.paymentMethod")),
  );
  const pay = document.createElement("button");
  pay.className = "btn"; pay.type = "submit"; pay.dataset.variant = "outline"; pay.textContent = t("ui.apply");
  primary.appendChild(pay);
  const payoff = document.createElement("div");
  payoff.className = "invoice-payment-row invoice-payment-payoff";
  payoff.append(
    createAmount({ id: `invoice-payoff-${invoice.id}`, value: currency(invoice.due_balance), readonly: true, label: t("ui.outstandingFor", { invoice: invoice.sequence || invoice.id }) }),
    createMethodSelector(payoff, t("checkout.paymentMethod")),
  );
  const payOff = document.createElement("button");
  payOff.className = "btn"; payOff.type = "submit"; payOff.formNoValidate = true; payOff.dataset.variant = "default"; payOff.textContent = t("ui.payOff");
  payoff.appendChild(payOff);
  payment.append(primary, payoff);
  return payment;
}

function invoiceRow(invoice) {
  const row = document.createElement("tr");
  row.className = "table-row invoice-row";
  const labels = ["Invoice", "Customer", "Date", "Status", "Total", "Balance", "Sales Person", "Actions"];
  [invoice.sequence || `#${invoice.id}`, invoice.client_name || "Walk-in customer"].forEach((value, index) => {
    const cell = document.createElement("td");
    cell.className = "table-cell";
    cell.dataset.label = labels[index];
    const trigger = document.createElement("button");
    trigger.className = "btn invoice-detail-trigger";
    trigger.type = "button";
    trigger.dataset.variant = "ghost";
    trigger.dataset.invoiceDetail = invoice.id;
    trigger.setAttribute("aria-expanded", String(expandedInvoiceId === invoice.id));
    if (index === 0) {
      const indicator = document.createElement("span");
      indicator.className = "invoice-disclosure";
      indicator.setAttribute("aria-hidden", "true");
      indicator.textContent = expandedInvoiceId === invoice.id ? "▾" : "▸";
      trigger.append(indicator);
    }
    trigger.append(document.createTextNode(value));
    cell.appendChild(trigger);
    row.appendChild(cell);
  });
  const date = document.createElement("td");
  date.className = "table-cell";
  date.dataset.label = labels[2];
  appendDateTime(date, invoice.date_create);
  row.appendChild(date);
  const status = document.createElement("td");
  status.className = "table-cell";
  status.dataset.label = labels[3];
  const badge = document.createElement("span");
  badge.className = `invoice-status invoice-status-${invoice.invoice_status}`;
  badge.textContent = invoiceStatusLabel(invoice.invoice_status);
  status.appendChild(badge);
  row.appendChild(status);
  [invoice.amount, Math.max(Number(invoice.due_balance || 0), 0)].forEach((amount, index) => {
    const cell = document.createElement("td");
    cell.className = "table-cell numeric";
    cell.dataset.label = labels[index + 4];
    cell.textContent = currency(amount);
    row.appendChild(cell);
  });
  const salesperson = document.createElement("td");
  salesperson.className = "table-cell invoice-salesperson";
  salesperson.dataset.label = labels[6];
  salesperson.textContent = invoice.login || "—";
  salesperson.title = invoice.login || "";
  row.appendChild(salesperson);
  const actions = document.createElement("td");
  actions.className = "table-cell invoice-actions";
  actions.dataset.label = labels[7];
  if (invoice.invoice_status !== "cancelled") {
    const cancel = document.createElement("button");
    cancel.className = "btn invoice-cancel"; cancel.type = "button"; cancel.dataset.variant = "ghost"; cancel.dataset.size = "sm"; cancel.dataset.cancelInvoice = invoice.id; cancel.textContent = t("ui.cancel");
    actions.appendChild(cancel);
  } else {
    actions.textContent = invoice.cancelled_by || "—";
  }
  row.appendChild(actions);
  return row;
}

function invoiceDetailsRow(invoice) {
  const detail = invoiceDetails.get(invoice.id);
  const row = document.createElement("tr");
  row.className = "table-row invoice-details-row";
  const cell = document.createElement("td");
  cell.className = "table-cell";
  cell.colSpan = 8;
  const card = document.createElement("section");
  card.className = "card invoice-details-card";
  if (!detail) {
    const content = document.createElement("div");
    content.className = "card-content invoice-details-skeleton";
    content.setAttribute("role", "status");
    content.setAttribute("aria-label", t("invoice.loadingDetails"));
    ["38%", "72%", "100%", "88%", "64%"].forEach((width) => content.appendChild(skeletonBlock("skeleton-line", width)));
    card.appendChild(content);
  } else {
    const header = document.createElement("div");
    header.className = "card-header";
    const title = document.createElement("h3");
    title.className = "card-title";
    title.textContent = detail.sequence || `Invoice #${detail.id}`;
    const description = document.createElement("p");
    description.className = "card-description";
    description.textContent = `${detail.client?.name || t("ui.walkInCustomer")} · ${detail.sale_type || t("ui.sales")} · ${detail.login || "—"}`;
    const headerCopy = document.createElement("div");
    headerCopy.append(title, description);
    header.appendChild(headerCopy);
    const printCopy = document.createElement("button");
    printCopy.className = "btn"; printCopy.type = "button"; printCopy.dataset.variant = "outline";
    printCopy.dataset.printInvoice = detail.id; printCopy.textContent = t("receipt.printCopy");
    header.appendChild(printCopy);
    if (detail.invoice_status === "open") header.appendChild(invoicePaymentForm(detail));
    if (["close", "cancelled"].includes(detail.invoice_status)) {
      const statusBadge = document.createElement("span");
      statusBadge.className = `invoice-status invoice-detail-status invoice-status-${detail.invoice_status}`;
      statusBadge.textContent = invoiceStatusLabel(detail.invoice_status);
      header.appendChild(statusBadge);
    }
    const content = document.createElement("div");
    content.className = "card-content";
    const paymentTableWrap = document.createElement("div");
    paymentTableWrap.className = "table-container invoice-payment-history";
    const paymentTitle = document.createElement("p");
    paymentTitle.className = "invoice-table-section-title";
    paymentTitle.textContent = t("invoice.payments");
    const paymentTable = document.createElement("table");
    paymentTable.className = "table";
    const paymentCaption = document.createElement("caption");
    paymentCaption.className = "sr-only";
    paymentCaption.textContent = t("invoice.recordedPayments");
    const paymentHead = document.createElement("thead");
    const paymentColumns = document.createElement("tr");
    paymentColumns.className = "table-row invoice-payment-columns";
    [t("invoice.payment"), t("ui.date"), t("invoice.user"), t("invoice.method"), t("checkout.amount"), t("ui.status"), t("ui.action")].forEach((label) => {
      const th = document.createElement("th");
      th.className = "table-head";
      th.scope = "col";
      th.textContent = label;
      paymentColumns.appendChild(th);
    });
    paymentHead.appendChild(paymentColumns);
    const paymentBody = document.createElement("tbody");
    if (!detail.payments.length) {
      const emptyRow = document.createElement("tr");
      emptyRow.className = "table-row";
      const emptyCell = document.createElement("td");
      emptyCell.className = "table-cell muted";
      emptyCell.colSpan = 7;
      emptyCell.textContent = t("invoice.noPayments");
      emptyRow.appendChild(emptyCell);
      paymentBody.appendChild(emptyRow);
    }
    detail.payments.forEach((payment) => {
      const paymentRow = document.createElement("tr");
      paymentRow.className = "table-row";
      const values = [t("invoice.payment"), payment.date_create ? new Date(payment.date_create.replace(" ", "T")).toLocaleDateString() : "—", payment.login || detail.login || "—", payment.type === "CC" ? t("checkout.card") : t("checkout.cash"), currency(payment.amount), detail.invoice_status === "close" ? t("invoice.complete") : t("invoice.partial")];
      values.forEach((value, index) => {
        const paymentCell = document.createElement("td");
        paymentCell.className = index === 4 ? "table-cell numeric" : "table-cell";
        paymentCell.textContent = value;
        paymentRow.appendChild(paymentCell);
      });
      const actionCell = document.createElement("td");
      actionCell.className = "table-cell invoice-payment-actions";
      const printPayment = document.createElement("button");
      printPayment.className = "btn"; printPayment.type = "button"; printPayment.dataset.variant = "outline"; printPayment.dataset.size = "sm";
      printPayment.dataset.printPayment = payment.id; printPayment.dataset.invoiceId = detail.id; printPayment.textContent = t("receipt.printPayment");
      actionCell.appendChild(printPayment);
      paymentRow.appendChild(actionCell);
      paymentBody.appendChild(paymentRow);
    });
    if (Number(detail.change_amount || 0) > 0) {
      const changeRow = document.createElement("tr");
      changeRow.className = "table-row invoice-change-row";
      const values = [t("checkout.change"), "—", "—", "—", currency(-Number(detail.change_amount)), t("invoice.complete")];
      values.forEach((value, index) => {
        const changeCell = document.createElement("td");
        changeCell.className = index === 4 ? "table-cell numeric" : "table-cell";
        changeCell.textContent = value;
        changeRow.appendChild(changeCell);
      });
      changeRow.appendChild(document.createElement("td")).className = "table-cell";
      paymentBody.appendChild(changeRow);
    }
    paymentTable.append(paymentCaption, paymentHead, paymentBody);
    paymentTableWrap.append(paymentTitle, paymentTable);
    const paymentMobileList = document.createElement("section");
    paymentMobileList.className = "invoice-payment-mobile-list";
    paymentMobileList.setAttribute("aria-label", t("invoice.recordedPayments"));
    const paymentMobileTitle = document.createElement("p");
    paymentMobileTitle.className = "invoice-table-section-title";
    paymentMobileTitle.textContent = t("invoice.payments");
    paymentMobileList.appendChild(paymentMobileTitle);
    if (!detail.payments.length) {
      const emptyMessage = document.createElement("p");
      emptyMessage.className = "invoice-payment-mobile-empty muted";
      emptyMessage.textContent = t("invoice.noPayments");
      paymentMobileList.appendChild(emptyMessage);
    }
    detail.payments.forEach((payment) => {
      const paymentCard = document.createElement("article");
      paymentCard.className = "invoice-payment-mobile-card";
      const paymentCardHeader = document.createElement("div");
      paymentCardHeader.className = "invoice-payment-mobile-card-header";
      const paymentName = document.createElement("strong");
      paymentName.textContent = t("invoice.payment");
      const paymentAmount = document.createElement("strong");
      paymentAmount.className = "numeric";
      paymentAmount.textContent = currency(payment.amount);
      paymentCardHeader.append(paymentName, paymentAmount);
      const paymentDetails = document.createElement("dl");
      paymentDetails.className = "invoice-payment-mobile-details";
      const dateParts = dateTimeParts(payment.date_create);
      [
        [t("ui.date"), dateParts ? `${dateParts.date} · ${dateParts.time}` : "—"],
        [t("invoice.user"), payment.login || detail.login || "—"],
        [t("invoice.method"), payment.type === "CC" ? t("checkout.card") : t("checkout.cash")],
        [t("ui.status"), detail.invoice_status === "close" ? t("invoice.complete") : t("invoice.partial")],
      ].forEach(([label, value]) => {
        const detailRow = document.createElement("div");
        const detailLabel = document.createElement("dt");
        detailLabel.textContent = label;
        const detailValue = document.createElement("dd");
        detailValue.textContent = value;
        detailRow.append(detailLabel, detailValue);
        paymentDetails.appendChild(detailRow);
      });
      paymentCard.append(paymentCardHeader, paymentDetails);
      const printPayment = document.createElement("button");
      printPayment.className = "btn invoice-payment-mobile-action"; printPayment.type = "button"; printPayment.dataset.variant = "outline"; printPayment.dataset.size = "sm";
      printPayment.dataset.printPayment = payment.id; printPayment.dataset.invoiceId = detail.id; printPayment.textContent = t("receipt.printPayment");
      paymentCard.appendChild(printPayment);
      paymentMobileList.appendChild(paymentCard);
    });
    if (Number(detail.change_amount || 0) > 0) {
      const changeCard = document.createElement("article");
      changeCard.className = "invoice-payment-mobile-card invoice-payment-mobile-change";
      const changeHeader = document.createElement("div");
      changeHeader.className = "invoice-payment-mobile-card-header";
      const changeName = document.createElement("strong");
      changeName.textContent = t("checkout.change");
      const changeAmount = document.createElement("strong");
      changeAmount.className = "numeric";
      changeAmount.textContent = currency(-Number(detail.change_amount));
      changeHeader.append(changeName, changeAmount);
      changeCard.appendChild(changeHeader);
      paymentMobileList.appendChild(changeCard);
    }
    const tableWrap = document.createElement("div");
    tableWrap.className = "table-container";
    const lineItemsTitle = document.createElement("p");
    lineItemsTitle.className = "invoice-table-section-title";
    lineItemsTitle.textContent = t("invoice.lineItems");
    const table = document.createElement("table");
    table.className = "table invoice-detail-lines";
    const caption = document.createElement("caption");
    caption.className = "sr-only";
    caption.textContent = t("invoice.lineItems");
    const head = document.createElement("thead");
    const headRow = document.createElement("tr");
    headRow.className = "table-row invoice-line-columns";
    [t("ui.product"), t("total.items"), t("invoice.unitPrice"), t("total.discount"), "", t("ui.total")].forEach((label) => {
      const th = document.createElement("th");
      th.className = "table-head"; th.scope = "col"; th.textContent = label; headRow.appendChild(th);
    });
    head.appendChild(headRow);
    const body = document.createElement("tbody");
    detail.lines.forEach((line) => {
      const lineRow = document.createElement("tr"); lineRow.className = "table-row";
      [line.product?.name || "—", line.quantity, currency(line.amount), discountDisplay(line.discount, line.discount_type, line.discount_input), "", currency(line.total_amount)].forEach((value, index) => {
        const td = document.createElement("td"); td.className = index ? "table-cell numeric" : "table-cell"; td.textContent = value; lineRow.appendChild(td);
      });
      body.appendChild(lineRow);
    });
    const foot = document.createElement("tfoot");
    [[t("total.subtotal"), detail.sub], [t("total.tax"), detail.tax_amount], ...(Number(detail.delivery_charge || 0) > 0 ? [[t("checkout.delivery"), detail.delivery_charge]] : []), [t("ui.total"), detail.amount]].forEach(([label, value], index) => {
      const summaryRow = document.createElement("tr");
      summaryRow.className = "table-row invoice-line-summary";
      if (label === t("ui.total")) summaryRow.classList.add("invoice-line-summary-total");
      const spacer = document.createElement("td");
      spacer.className = "table-cell";
      spacer.colSpan = 3;
      spacer.setAttribute("aria-hidden", "true");
      const saleDiscount = document.createElement("td");
      saleDiscount.className = "table-cell numeric invoice-line-summary-discount";
      saleDiscount.textContent = index === 0 && Number(detail.discount || 0) ? currency(detail.discount) : "-";
      const summaryLabel = document.createElement("th");
      summaryLabel.className = "table-cell";
      summaryLabel.scope = "row";
      summaryLabel.textContent = label;
      const summaryAmount = document.createElement("td");
      summaryAmount.className = "table-cell numeric";
      summaryAmount.textContent = currency(value);
      summaryRow.append(spacer, saleDiscount, summaryLabel, summaryAmount);
      foot.appendChild(summaryRow);
    });
    table.append(caption, head, body, foot); tableWrap.append(lineItemsTitle, table);
    const memo = detail.additional_info?.trim();
    if (memo) {
      const memoSection = document.createElement("section");
      memoSection.className = "invoice-memo";
      const memoText = document.createElement("p");
      memoText.className = "invoice-memo-text";
      memoText.textContent = memo;
      const salesperson = document.createElement("div");
      salesperson.className = "invoice-memo-salesperson";
      const avatar = document.createElement("span");
      avatar.className = "avatar invoice-memo-avatar";
      avatar.setAttribute("aria-hidden", "true");
      const image = document.createElement("img");
      image.className = "avatar-image";
      image.alt = "";
      const avatarUrl = avatarSource(detail.salesperson?.pic);
      image.hidden = !avatarUrl;
      if (avatarUrl) image.src = avatarUrl;
      const fallback = document.createElement("span");
      fallback.className = "avatar-fallback";
      fallback.textContent = (detail.salesperson?.name || detail.login || "?").trim().slice(0, 1).toUpperCase();
      fallback.hidden = Boolean(avatarUrl);
      image.onerror = () => { image.hidden = true; fallback.hidden = false; };
      avatar.append(image, fallback);
      const name = document.createElement("span");
      name.textContent = detail.salesperson?.name || detail.login || "—";
      salesperson.append(avatar, name);
      memoSection.append(memoText, salesperson);
      content.append(paymentTableWrap, paymentMobileList, tableWrap, memoSection);
    } else {
      content.append(paymentTableWrap, paymentMobileList, tableWrap);
    }
    card.append(header, content);
  }
  cell.appendChild(card); row.appendChild(cell);
  return row;
}

function renderInvoices() {
  if (invoiceLoading && !invoices.length) {
    invoiceTableBody.replaceChildren(...invoiceSkeletonRows());
    return;
  }
  invoiceTableBody.replaceChildren(...invoices.flatMap((invoice) => expandedInvoiceId === invoice.id ? [invoiceRow(invoice), invoiceDetailsRow(invoice)] : [invoiceRow(invoice)]));
  if (!invoices.length && !invoiceLoading && !invoiceLoadError) invoiceReportStatus.textContent = t("ui.noInvoices");
}

function invoiceSkeletonRows() {
  return Array.from({ length: 6 }, () => {
    const row = document.createElement("tr");
    row.className = "table-row skeleton-table-row";
    ["58%", "70%", "62%", "54%", "66%", "60%", "68%", "50%"].forEach((width, index) => {
      const cell = document.createElement("td");
      cell.className = `table-cell${[4, 5].includes(index) ? " numeric" : ""}`;
      cell.appendChild(skeletonBlock("skeleton-line", width));
      row.appendChild(cell);
    });
    return row;
  });
}

function screenLoadingSkeleton() {
  const skeleton = document.createElement("div");
  skeleton.className = "screen-loading-skeleton";
  skeleton.setAttribute("role", "status");
  skeleton.setAttribute("aria-label", "Loading screen content");
  const header = document.createElement("div");
  header.className = "screen-loading-header";
  header.append(skeletonBlock("skeleton-title", "12rem"), skeletonBlock("skeleton-control", "min(42%, 28rem)"), skeletonBlock("skeleton-control", "9rem"));
  const cards = document.createElement("div");
  cards.className = "screen-loading-cards";
  ["2fr", "1fr", "1fr"].forEach((span) => {
    const card = document.createElement("div");
    card.className = "screen-loading-card";
    card.style.gridColumn = `span ${span === "2fr" ? 2 : 1}`;
    card.append(skeletonBlock("skeleton-line", "44%"), skeletonBlock("skeleton-line skeleton-value", "62%"), skeletonBlock("skeleton-line", "76%"));
    cards.appendChild(card);
  });
  const table = document.createElement("div");
  table.className = "screen-loading-table";
  Array.from({ length: 7 }, () => {
    const row = document.createElement("div");
    row.className = "screen-loading-table-row";
    ["72%", "56%", "64%", "52%", "58%", "48%", "50%", "60%", "56%", "52%"].forEach((width) => row.appendChild(skeletonBlock("skeleton-line", width)));
    table.appendChild(row);
  });
  skeleton.append(header, cards, table);
  return skeleton;
}

function setScreenLoading(screen, loading) {
  screen.classList.toggle("is-screen-loading", loading);
  const current = screen.querySelector(":scope > .screen-loading-skeleton");
  if (loading && !current) screen.appendChild(screenLoadingSkeleton());
  if (!loading) current?.remove();
}

function invoiceScrollContainer() {
  const overflowY = getComputedStyle(catalogPanel).overflowY;
  return ["auto", "scroll"].includes(overflowY) ? catalogPanel : document.scrollingElement;
}

function renderInvoicesPreservingScroll(invoiceId) {
  expandedInvoiceId = invoiceId;
  const currentTrigger = invoiceTableBody.querySelector(`[data-invoice-detail="${invoiceId}"]`);
  const currentRow = currentTrigger?.closest("tr");
  const scrollContainer = invoiceScrollContainer();
  const offset = currentRow?.getBoundingClientRect().top;

  renderInvoices();

  requestAnimationFrame(() => {
    const refreshedTrigger = invoiceTableBody.querySelector(`[data-invoice-detail="${invoiceId}"]`);
    const refreshedRow = refreshedTrigger?.closest("tr");
    if (offset !== undefined && refreshedRow) scrollContainer.scrollTop += refreshedRow.getBoundingClientRect().top - offset;
    else refreshedTrigger?.scrollIntoView({ block: "nearest" });
  });
}

function sortInvoices() {
  const { key, direction } = invoiceSort;
  const factor = direction === "asc" ? 1 : -1;
  invoices.sort((left, right) => {
    const leftValue = key === "sequence" ? left.sequence : left[key];
    const rightValue = key === "sequence" ? right.sequence : right[key];
    if (["amount", "due_balance"].includes(key)) return (Number(leftValue || 0) - Number(rightValue || 0)) * factor;
    return String(leftValue || "").localeCompare(String(rightValue || ""), undefined, { numeric: true, sensitivity: "base" }) * factor;
  });
}

async function loadInvoices({ reset = false, preserveExpanded = false, quiet = false } = {}) {
  if (invoiceLoading || (!reset && !invoiceHasMore)) return;
  const refreshedExpandedId = preserveExpanded ? expandedInvoiceId : null;
  if (reset) { invoiceCursor = null; invoiceHasMore = true; invoices = []; expandedInvoiceId = null; }
  invoiceLoading = true;
  invoiceLoadError = false;
  if (reset && !quiet) setScreenLoading(invoiceReport, true);
  renderInvoices();
  invoiceReportStatus.textContent = invoices.length ? t("ui.loadingMoreInvoices") : t("ui.loadingInvoices");
  try {
    const page = await salesReport(storeId, invoiceCursor, invoiceSearch.value.trim(), invoiceDateFrom.value, invoiceDateTo.value, invoiceStatusFilter);
    invoices = invoices.concat(page.entries);
    sortInvoices();
    if (refreshedExpandedId && invoices.some((invoice) => invoice.id === refreshedExpandedId)) expandedInvoiceId = refreshedExpandedId;
    invoiceCursor = page.next_cursor;
    invoiceHasMore = page.has_more;
    updateInvoiceSummary(page.summary);
    renderInvoices();
    if (reset) invoicesStale = false;
    invoiceReportStatus.textContent = invoiceHasMore ? t(mobileQuery.matches ? "ui.scrollInvoices" : "product.scroll") : t("ui.invoicesLoaded", { count: invoices.length });
  } catch (error) {
    console.error(error);
    invoiceLoadError = true;
    invoiceReportStatus.textContent = t("ui.invoicesLoadError");
  } finally { invoiceLoading = false; renderInvoices(); if (reset && !quiet) setScreenLoading(invoiceReport, false); }
}

function openInvoiceReport() {
  closeUsersPage();
  customersScreen.hidden = true;
  customerDetailScreen.hidden = true;
  checkoutFlow.hidden = true;
  closeOperations();
  catalogPanel.dataset.view = "invoices";
  appShell.classList.add("invoice-view");
  invoiceReport.hidden = false;
  updateInvoiceStickyOffset();
  selectSidebar("sales-report-nav");
  if (!invoices.length || invoicesStale) {
    loadInvoices({ reset: true });
  }
  requestAnimationFrame(() => document.querySelector("#invoice-report-title").focus());
}

function closeInvoiceReport() {
  invoiceReport.hidden = true;
  if (catalogPanel.dataset.view === "invoices") delete catalogPanel.dataset.view;
  appShell.classList.remove("invoice-view");
  selectSidebar("pos-nav");
}

function dateTimeParts(value) {
  if (!value) return null;
  const date = new Date(String(value).replace(" ", "T"));
  if (Number.isNaN(date.getTime())) return null;
  return { date: date.toLocaleDateString("en-GB"), time: date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", hour12: true }) };
}
function appendDateTime(cell, value) {
  const parts = dateTimeParts(value);
  if (!parts) { cell.textContent = "—"; return; }
  const date = document.createElement("span"); date.className = "invoice-date"; date.textContent = parts.date;
  const time = document.createElement("span"); time.className = "invoice-time"; time.textContent = parts.time;
  cell.append(date, time);
}
function dateTimeMarkup(value) {
  const parts = dateTimeParts(value);
  return parts ? `<span class="invoice-date">${parts.date}</span><span class="invoice-time">${parts.time}</span>` : "—";
}
function formatOperationDate(value) { return dateTimeMarkup(value); }
function closeOperations() { inventoryScreen.hidden = true; ordersScreen.hidden = true; purchaseOrderScreen.hidden = true; companySettingsScreen.hidden = true; }
function openInventory() { openPos(); closeOperations(); catalogPanel.dataset.view = "inventory"; appShell.classList.add("invoice-view"); inventoryScreen.hidden = false; selectSidebar("inventory-nav"); loadInventory(); requestAnimationFrame(() => document.querySelector("#inventory-title").focus()); }
function openOrders() { openPos(); closeOperations(); catalogPanel.dataset.view = "orders"; appShell.classList.add("invoice-view"); ordersScreen.hidden = false; selectSidebar("orders-nav"); loadOrders(); requestAnimationFrame(() => document.querySelector("#orders-title").focus()); }
function companySettingField(labelText, name, value = "", { required = false, type = "text", multiline = false } = {}) {
  const field = document.createElement("div"); field.className = "form-field";
  const id = `company-setting-${name}-${uuid()}`;
  const label = document.createElement("label"); label.className = "label"; label.htmlFor = id; label.textContent = labelText;
  const input = multiline ? document.createElement("textarea") : document.createElement("input"); input.className = "input"; input.id = id; input.name = name; if (!multiline) input.type = type; input.value = value || ""; input.required = required;
  field.append(label, input); return field;
}
function storeLogoField(entry = null) {
  const field = document.createElement("div"); field.className = "form-field store-logo-field";
  const dropzone = document.createElement("div"); dropzone.className = "product-image-dropzone store-logo-dropzone"; dropzone.tabIndex = 0; dropzone.setAttribute("role", "button");
  const id = `store-logo-${uuid()}`;
  dropzone.innerHTML = `<label class="label" for="${id}">Store logo</label><p class="field-description">Drop an image here or choose a file (max 10 MB). It will be resized and stored as Base64.</p><input id="${id}" class="input" name="store-logo-file" type="file" accept="image/*" />`;
  const preview = document.createElement("img"); preview.className = "product-image-preview store-logo-preview"; preview.alt = "Store logo preview"; preview.hidden = !entry?.logo; if (entry?.logo) preview.src = entry.logo;
  dropzone.prepend(preview); field.append(dropzone);
  if (entry?.logo) { const remove = document.createElement("button"); remove.type = "button"; remove.className = "btn store-logo-remove"; remove.dataset.variant = "outline"; remove.dataset.removeStoreLogo = ""; remove.textContent = "Remove logo"; field.append(remove); }
  return field;
}
function companySettingForm(kind, entry = null) {
  const form = document.createElement("form"); form.className = "form company-setting-form"; form.dataset.kind = kind;
  form.appendChild(companySettingField(kind === "price-list" ? "Price list label" : kind === "provider" ? "Provider name" : "Store name", "name", entry?.label || entry?.name, { required: true }));
  if (kind === "store") {
    const company = document.createElement("p"); company.className = "field-description store-company-context"; company.textContent = `Company: ${companySettingsData.company?.name || "Current company"}`; form.append(company, companySettingField("Slogan", "slogan", entry?.slogan), companySettingField("Address", "address", entry?.address, { multiline: true }), storeLogoField(entry));
    preparedStoreLogo = entry?.logo || null; selectedStoreLogoFile = null; storeLogoPreparationTask = null;
  }
  const actions = document.createElement("div"); actions.className = "form-actions";
  const cancel = document.createElement("button"); cancel.className = "btn"; cancel.type = "button"; cancel.dataset.variant = "outline"; cancel.dataset.companySettingCancel = ""; cancel.textContent = "Cancel";
  const save = document.createElement("button"); save.className = "btn"; save.type = "submit"; save.dataset.variant = "default"; save.textContent = entry ? "Save" : "Create";
  actions.append(cancel, save); form.appendChild(actions); return form;
}
function companySettingRow(kind, entry) {
  const row = document.createElement("div"); row.className = "company-setting-row";
  const copy = document.createElement("div");
  if (kind === "store" && entry.logo) { const logo = document.createElement("img"); logo.className = "store-logo-thumbnail"; logo.src = entry.logo; logo.alt = ""; copy.appendChild(logo); }
  const title = document.createElement("strong"); title.textContent = entry.label || entry.name;
  const description = document.createElement("p"); description.className = "field-description"; description.textContent = kind === "store" ? [entry.slogan, entry.address].filter(Boolean).join(" · ") || "No store details provided" : entry.price_key || "";
  copy.append(title, description);
  const actions = document.createElement("div"); actions.className = "company-setting-actions";
  [["Edit", "outline", "edit"], ...(kind === "store" ? [] : [["Delete", "destructive", "delete"]])].forEach(([text, variant, action]) => { const button = document.createElement("button"); button.className = "btn"; button.type = "button"; button.dataset.variant = variant; button.dataset.size = "sm"; button.dataset.companySettingAction = action; button.dataset.kind = kind; button.dataset.id = entry.id; button.textContent = text; actions.appendChild(button); });
  row.append(copy, actions); return row;
}
function sequenceSetForm(entry = null) {
  const form = document.createElement("form"); form.className = "form company-setting-form";
  [["Name", "name", entry?.name, "text"], ["Code", "code", entry?.code, "text"], ["Prefix", "prefix", entry?.prefix, "text"], ["Digits", "fill", entry?.fill ?? 8, "number"], ["Increment", "increment_by", entry?.increment_by ?? 1, "number"], ["Next number", "current_seq", entry?.current_seq ?? 0, "number"]].forEach(([label, name, value, type]) => form.appendChild(companySettingField(label, name, value, { required: true, type })));
  const actions = document.createElement("div"); actions.className = "form-actions"; actions.innerHTML = '<button class="btn" type="button" data-variant="outline" data-sequence-cancel>Cancel</button><button class="btn" type="submit" data-variant="default">Save</button>'; form.appendChild(actions); return form;
}
function sequenceSetRow(entry) {
  const row = document.createElement("div"); row.className = "company-setting-row";
  const copy = document.createElement("div"); const title = document.createElement("strong"); title.textContent = `${entry.code} · ${entry.name}`; const description = document.createElement("p"); description.className = "field-description"; description.textContent = `${entry.prefix}${String(entry.current_seq).padStart(entry.fill, "0")} · increments by ${entry.increment_by}`; copy.append(title, description);
  const actions = document.createElement("div"); actions.className = "company-setting-actions"; [["Edit", "outline", "edit"], ["Delete", "destructive", "delete"]].forEach(([label, variant, action]) => { const button = document.createElement("button"); button.className = "btn"; button.type = "button"; button.dataset.variant = variant; button.dataset.size = "sm"; button.dataset.sequenceAction = action; button.dataset.id = entry.id; button.textContent = label; actions.appendChild(button); }); row.append(copy, actions); return row;
}
function renderCompanySettings() {
  const company = companySettingsData.company;
  companySettingsCompany.textContent = company ? [company.name, company.rnc ? `RNC ${company.rnc}` : ""].filter(Boolean).join(" · ") : "Company information is unavailable.";
  const renderList = (container, kind, entries, empty) => {
    container.replaceChildren();
    if (editingCompanySetting?.kind === kind && editingCompanySetting.id === "new") container.appendChild(companySettingForm(kind));
    entries.forEach((entry) => { if (editingCompanySetting?.kind === kind && Number(editingCompanySetting.id) === Number(entry.id)) container.appendChild(companySettingForm(kind, entry)); else container.appendChild(companySettingRow(kind, entry)); });
    if (!entries.length && !(editingCompanySetting?.kind === kind)) { const message = document.createElement("p"); message.className = "field-description company-settings-empty"; message.textContent = empty; container.appendChild(message); }
  };
  renderList(priceListsContent, "price-list", companySettingsData.price_lists || [], "No price lists yet.");
  renderList(storesContent, "store", companySettingsData.stores || [], "No stores yet.");
  renderList(providersContent, "provider", companySettingsData.providers || [], "No providers yet.");
  sequenceSetsContent.replaceChildren();
  if (editingCompanySetting?.kind === "sequence" && editingCompanySetting.id === "new") sequenceSetsContent.appendChild(sequenceSetForm());
  (companySettingsData.sequence_sets || []).forEach((entry) => sequenceSetsContent.appendChild(editingCompanySetting?.kind === "sequence" && Number(editingCompanySetting.id) === Number(entry.id) ? sequenceSetForm(entry) : sequenceSetRow(entry)));
  if (!(companySettingsData.sequence_sets || []).length && editingCompanySetting?.kind !== "sequence") { const message = document.createElement("p"); message.className = "field-description company-settings-empty"; message.textContent = "No sequences configured. Add CF, VF, and DV to complete sales."; sequenceSetsContent.appendChild(message); }
}
async function loadCompanySettings() {
  companySettingsStatus.textContent = t("ui.loadingCompanySettings");
  try { companySettingsData = await companySettings(); renderCompanySettings(); renderSequenceOptions(); companySettingsStatus.textContent = ""; }
  catch (error) { console.error(error); companySettingsStatus.textContent = error.message || "Company settings could not be loaded."; }
}
function renderSequenceOptions() {
  const container = document.querySelector(".sequence-options");
  const selectedCode = container.querySelector('[data-sequence][data-variant="default"]')?.dataset.sequence || "CF";
  const sequences = (companySettingsData.sequence_sets || []).filter((sequence) => ["CF", "VF", "DV"].includes(sequence.code));
  if (!sequences.length) return;
  const buttons = document.createElement("div"); buttons.className = "sequence-option-buttons";
  sequences.forEach((sequence) => {
    const button = document.createElement("button"); button.className = "btn"; button.type = "button"; button.dataset.sequence = sequence.code; button.dataset.sequenceDescription = sequence.name || sequence.code; button.dataset.variant = sequence.code === selectedCode ? "default" : "secondary"; button.textContent = sequence.code;
    buttons.appendChild(button);
  });
  const description = document.createElement("span"); description.className = "sequence-option-description";
  container.replaceChildren(buttons, description);
  updateSequenceDescription();
}
function updateSequenceDescription() {
  const selected = document.querySelector('[data-sequence][data-variant="default"]');
  const description = document.querySelector(".sequence-option-description");
  if (description) description.textContent = selected?.dataset.sequenceDescription || selected?.dataset.sequence || "";
}
function openCompanySettings() { openPos(); closeOperations(); catalogPanel.dataset.view = "company-settings"; appShell.classList.add("invoice-view"); companySettingsScreen.hidden = false; selectSidebar("company-settings-nav"); loadCompanySettings(); requestAnimationFrame(() => document.querySelector("#company-settings-title").focus()); }
function sortOperationEntries(entries, sort) { const factor = sort.direction === "asc" ? 1 : -1; return [...entries].sort((a, b) => { const left = a[sort.key] ?? "", right = b[sort.key] ?? ""; return (typeof left === "number" && typeof right === "number" ? left - right : String(left).localeCompare(String(right), undefined, { numeric: true, sensitivity: "base" })) * factor; }); }
function renderInventory() {
  const q = inventorySearchInput.value.trim().toLowerCase();
  const entries = sortOperationEntries(q ? inventoryEntries.filter((e) => `${e.product_name || ""} ${e.product_code || ""}`.toLowerCase().includes(q)) : inventoryEntries, inventorySort);
  const rows = entries.flatMap((entry) => {
    const row = document.createElement("tr");
    row.className = "table-row";
    row.dataset.inventoryProductId = entry.product_id;
    const labels = ["Product", "SKU", "Store", "Cost", "Price", "Total quantity", "Current quantity", "Previous quantity", "Last updated", "Updated by"];
    [entry.product_name || `Product #${entry.product_id}`, entry.product_code || "—", entry.store_name || "Current store", currency(entry.product_cost), entry.product_price == null ? "—" : currency(entry.product_price), entry.total_quantity ?? entry.quantity ?? 0, entry.quantity ?? 0, entry.prev_quantity ?? "—", entry.last_update, entry.user_updated || "—"].forEach((value, index) => {
      const cell = document.createElement("td"); cell.className = "table-cell";
      cell.dataset.label = labels[index];
      if (index === 0) { const button = document.createElement("button"); button.className = "btn"; button.type = "button"; button.dataset.variant = "link"; button.dataset.editProduct = entry.product_id; button.textContent = value; cell.appendChild(button); }
      else if (index === 1) {
        const isLoading = loadingTraceProductId === entry.product_id;
        const isExpanded = expandedInventoryDetail?.productId === entry.product_id && expandedInventoryDetail.type === "trace" && !isLoading;
        cell.innerHTML = `<button class="btn inventory-sku-trace" type="button" data-variant="link" data-product-traces="${entry.product_id}" aria-expanded="${String(isExpanded)}" title="${t("ui.showProductHistory")}"${isLoading ? ' aria-busy="true"' : ""}>${isLoading ? '<span class="inventory-quantity-spinner" aria-hidden="true"></span>' : value}</button>`;
      } else if (index === 5) {
        const isLoading = loadingStoreQuantitiesProductId === entry.product_id;
        const isExpanded = expandedInventoryDetail?.productId === entry.product_id && expandedInventoryDetail.type === "quantity" && !isLoading;
        cell.innerHTML = `<button class="btn inventory-total-quantity" type="button" data-variant="link" data-total-quantity="${entry.product_id}" title="Show Quantity per Store" aria-expanded="${String(isExpanded)}"${isLoading ? ' aria-busy="true" aria-label="Loading quantity per store"' : ""}><span class="inventory-total-quantity-indicator" aria-hidden="true">${isExpanded ? "▾" : "▸"}</span>${isLoading ? '<span class="inventory-quantity-spinner" aria-hidden="true"></span>' : value}</button>`;
      }
      else if (index === 8) appendDateTime(cell, entry.last_update);
      else if (index === 6) {
        if (editingInventoryProductId === entry.product_id) cell.innerHTML = `<div class="inventory-inline-editor"><label class="sr-only" for="inventory-quantity-${entry.product_id}">Current quantity</label><input id="inventory-quantity-${entry.product_id}" class="input" type="number" inputmode="numeric" value="${entry.quantity ?? 0}" aria-label="Current quantity for ${entry.product_name}"><button class="btn" type="button" data-variant="default" data-size="sm" data-save-inventory="${entry.product_id}">Update</button><button class="btn" type="button" data-variant="ghost" data-size="sm" data-cancel-inventory>Cancel</button></div>`;
        else cell.innerHTML = `<div class="inventory-inline-editor"><span>${value}</span><button class="btn" type="button" data-variant="outline" data-size="sm" data-adjust-product="${entry.product_id}">Update</button></div>`;
      } else cell.textContent = value;
      row.appendChild(cell);
    });
    if (expandedInventoryDetail?.productId === entry.product_id && expandedInventoryDetail.type === "trace") {
      if (loadingTraceProductId === entry.product_id) return [row];
      const traceRow = document.createElement("tr");
      traceRow.className = "table-row inventory-traces-row";
      const traceCell = document.createElement("td"); traceCell.className = "table-cell"; traceCell.colSpan = labels.length;
      traceCell.innerHTML = traceHistoryMarkup(expandedProductTraces);
      traceRow.appendChild(traceCell);
      return [row, traceRow];
    }
    if (expandedInventoryDetail?.productId !== entry.product_id || expandedInventoryDetail.type !== "quantity") return [row];
    if (loadingStoreQuantitiesProductId === entry.product_id) return [row];
    const storeRows = expandedStoreQuantities.map((storeEntry) => {
      const storeRow = document.createElement("tr");
      storeRow.className = "table-row inventory-store-row";
      storeRow.dataset.inventoryProductId = entry.product_id;
      ["", "", "Store"].forEach((value, index) => { const cell = document.createElement("td"); cell.className = "table-cell"; cell.dataset.label = labels[index]; cell.textContent = value; storeRow.appendChild(cell); });
      const storeCell = document.createElement("td"); storeCell.className = "table-cell inventory-store-name"; storeCell.colSpan = 2; storeCell.dataset.label = "Store"; storeCell.textContent = storeEntry.store_name; storeRow.appendChild(storeCell);
      [""].forEach((value) => { const cell = document.createElement("td"); cell.className = "table-cell"; cell.dataset.label = labels[5]; cell.textContent = value; storeRow.appendChild(cell); });
      const quantityCell = document.createElement("td"); quantityCell.className = "table-cell"; quantityCell.dataset.label = labels[6]; quantityCell.innerHTML = `<div class="inventory-inline-editor"><label class="sr-only" for="inventory-store-quantity-${entry.product_id}-${storeEntry.store_id}">Quantity for ${storeEntry.store_name}</label><input id="inventory-store-quantity-${entry.product_id}-${storeEntry.store_id}" class="input" type="number" inputmode="numeric" value="${storeEntry.quantity ?? 0}" aria-label="Quantity for ${storeEntry.store_name}"><button class="btn" type="button" data-variant="default" data-size="sm" data-save-store-inventory="${entry.product_id}" data-store-id="${storeEntry.store_id}">Update</button></div>`; storeRow.appendChild(quantityCell);
      [storeEntry.prev_quantity ?? "—", storeEntry.last_update, storeEntry.user_updated || "—"].forEach((value, offset) => { const cell = document.createElement("td"); cell.className = "table-cell"; cell.dataset.label = labels[offset + 7]; if (offset === 1) appendDateTime(cell, value); else cell.textContent = value; storeRow.appendChild(cell); });
      return storeRow;
    });
    return [row, ...storeRows];
  });
  inventoryTableBody.replaceChildren(...rows);
  inventoryStatus.textContent = entries.length ? `${entries.length} products` : "No inventory found.";
}
function traceHistoryMarkup(traces) {
  if (!traces.length) return '<p class="field-description">No trace history yet.</p>';
  const title = { sale: "Sale", inventory_adjustment: "Adjustment", purchase: "Purchase", store_transfer_out: "Transfer out", store_transfer_in: "Transfer in" };
  return `<div class="inventory-trace-wrap"><table class="table inventory-trace-table"><thead><tr class="table-row"><th class="table-head">${t("ui.date")}</th><th class="table-head">${t("ui.action")}</th><th class="table-head">${t("ui.store")}</th><th class="table-head">${t("checkout.change")}</th><th class="table-head">${t("ui.previousQuantity")} → ${t("ui.currentQuantity")}</th><th class="table-head">${t("ui.updatedBy")}</th><th class="table-head">${t("ui.customer")}</th></tr></thead><tbody>${traces.map((trace) => {
    const sign = Number(trace.quantity_change) > 0 ? "+" : "";
    const provider = trace.metadata?.provider_name || trace.metadata?.["provider_name"];
    const context = [trace.customer_name ? `Customer: ${trace.customer_name}` : "", provider ? `Provider: ${provider}` : "", trace.destination_store_name ? `To: ${trace.destination_store_name}` : "", trace.source_store_name && trace.event_type === "store_transfer_in" ? `From: ${trace.source_store_name}` : "", trace.reference_type ? `${trace.reference_type.replaceAll("_", " ")} #${trace.reference_id}` : ""].filter(Boolean).join(" · ") || "—";
    return `<tr class="table-row"><td class="table-cell">${dateTimeMarkup(trace.inserted_at)}</td><td class="table-cell">${title[trace.event_type] || trace.event_type}</td><td class="table-cell">${trace.store_name || "—"}</td><td class="table-cell numeric">${sign}${trace.quantity_change}</td><td class="table-cell numeric">${trace.quantity_before} → ${trace.quantity_after}</td><td class="table-cell">${trace.operator_username || "—"}</td><td class="table-cell">${context}</td></tr>`;
  }).join("")}</tbody></table></div>`;
}
function percentage(value) { return `${(Number(value || 0) * 100).toFixed(1)}%`; }
function compactList(items, formatter, empty = "No activity") { return Array.isArray(items) && items.length ? items.map(formatter).join(" · ") : empty; }
function inventoryMetric(title, value, description, tone = "", filter = "") {
  const card = document.createElement("article");
  card.className = `card inventory-summary-card ${tone}`.trim();
  const body = document.createElement(filter ? "button" : "div");
  if (filter) {
    body.className = "btn inventory-kpi";
    body.type = "button";
    body.dataset.inventoryFilter = filter;
    body.dataset.variant = inventoryFilter === filter ? "secondary" : "ghost";
    body.setAttribute("aria-pressed", String(inventoryFilter === filter));
    body.setAttribute("aria-label", t("inventory.filter", { title: title.toLowerCase() }));
  }
  const header = document.createElement("div"); header.className = "card-header";
  const label = document.createElement("p"); label.className = "card-title"; label.textContent = title;
  const content = document.createElement("div"); content.className = "card-content";
  const metric = document.createElement("p"); metric.className = "inventory-kpi-value numeric"; metric.textContent = value;
  const detail = document.createElement("p"); detail.className = "inventory-kpi-detail"; detail.textContent = description;
  header.appendChild(label); content.append(metric, detail); body.append(header, content); card.appendChild(body);
  return card;
}
function inventoryValuationMetric(summary) {
  const card = document.createElement("article");
  card.className = "card inventory-summary-card inventory-summary-valuation";
  const header = document.createElement("div"); header.className = "card-header";
  const label = document.createElement("p"); label.className = "card-title"; label.textContent = t("inventory.valuation");
  const content = document.createElement("div"); content.className = "card-content inventory-valuation-content";
  const company = document.createElement("div"); company.className = "inventory-valuation-company";
  const total = document.createElement("p"); total.className = "inventory-kpi-value numeric"; total.textContent = currency(summary.company_inventory_valuation);
  const caption = document.createElement("p"); caption.className = "inventory-valuation-caption numeric"; caption.textContent = t("inventory.companyTotal");
  const breakdown = document.createElement("div"); breakdown.className = "inventory-valuation-breakdown";
  (Array.isArray(summary.inventory_valuation_by_store) ? summary.inventory_valuation_by_store : []).forEach((store) => {
    const item = document.createElement("div"); item.className = "inventory-valuation-store";
    const amount = document.createElement("p"); amount.className = "inventory-valuation-store-amount numeric"; amount.textContent = currency(store.inventory_valuation);
    const name = document.createElement("p"); name.className = "inventory-valuation-store-name"; name.textContent = store.store_name || "Store";
    item.append(amount, name); breakdown.appendChild(item);
  });
  company.append(total, caption); header.appendChild(label); content.append(company, breakdown); card.append(header, content);
  return card;
}
function renderInventorySummary(summary) {
  if (!summary) return;
  const bestProducts = compactList(summary.best_products, (item) => `${item.product_name}: ${currency(item.net_revenue)}`);
  const slowestProducts = compactList(summary.slowest_products, (item) => `${item.product_name}: ${t("inventory.units", { count: Number(item.net_units).toFixed(0) })}`, t("inventory.noActivity"));
  const salesMix = compactList(summary.sales_mix, (item) => `${item.sale_type || t("ui.sales")}/${item.login || "—"}: ${currency(item.net_sales)}`, t("inventory.noActivity"));
  const paymentMix = compactList(summary.payment_method_mix, (item) => `${item.type}: ${currency(item.amount)}`);
  const cards = [
    inventoryValuationMetric(summary),
    inventoryMetric(t("inventory.negativeStock"), t("inventory.skus", { count: Number(summary.negative_stock_sku_count || 0) }), `${t("inventory.units", { count: Number(summary.negative_stock_units || 0) })} · ${currency(summary.negative_stock_value)}`, "inventory-summary-negative inventory-summary-compact", "negative"),
    inventoryMetric(t("inventory.uncosted"), t("inventory.skus", { count: Number(summary.uncosted_inventory_sku_count || 0) }), `${t("inventory.units", { count: Number(summary.uncosted_inventory_units || 0) })} · ${t("ui.cost")}`, "inventory-summary-warning inventory-summary-compact", "uncosted"),
    inventoryMetric(t("inventory.stockout"), percentage(summary.zero_stock_rate), `${Number(summary.zero_stock_sku_count || 0)} / ${t("inventory.skus", { count: Number(summary.inventoried_sku_count || 0) })}`, "inventory-summary-warning"),
    inventoryMetric(t("inventory.netSales"), currency(summary.net_sales), `${Number(summary.sale_transaction_count || 0)} ${t("ui.sales").toLowerCase()}`),
    inventoryMetric(t("inventory.salesMix"), currency(summary.net_sales), salesMix),
    inventoryMetric(t("inventory.averageOrder"), currency(summary.average_order_value), `${Number(summary.units_per_order || 0).toFixed(1)} ${t("inventory.units", { count: "" }).trim()}`),
    inventoryMetric(t("inventory.bestProducts"), bestProducts, slowestProducts),
    inventoryMetric(t("inventory.discountRate"), percentage(summary.discount_rate), `${currency(summary.net_discount)} ${t("total.discount").toLowerCase()}`),
    inventoryMetric(t("inventory.paymentMix"), paymentMix, t("invoice.recordedPayments")),
    inventoryMetric(t("inventory.retention"), `${Number(summary.returning_customer_count || 0)} ${t("ui.customers").toLowerCase()}`, `${Number(summary.purchasing_customer_count || 0)} ${t("ui.customers").toLowerCase()} · ${currency(summary.average_customer_value)}`),
    inventoryMetric(t("inventory.flow"), `${Number(summary.open_purchase_order_count || 0)} ${t("ui.purchaseOrders").toLowerCase()}`, `${Number(summary.closed_purchase_order_count || 0)} ${t("order.closed").toLowerCase()} · ${percentage(summary.receiving_completion_rate)}`)
  ];
  inventorySummaryGrid.replaceChildren(...cards);
}
function focusInventoryRow(productId) {
  if (!productId) return;
  const row = inventoryTableBody.querySelector(`[data-inventory-product-id="${productId}"]`);
  if (!row) return;
  row.scrollIntoView({ block: "nearest", behavior: "smooth" });
  row.querySelector("[data-adjust-product], [data-save-inventory]")?.focus({ preventScroll: true });
}
function renderInventoryWithoutMoving() {
  const scrollTop = catalogPanel.scrollTop;
  renderInventory();
  catalogPanel.scrollTop = scrollTop;
}
async function loadInventory(focusProductId = null, { preserveContext = false } = {}) {
  const scrollTop = preserveContext ? catalogPanel.scrollTop : null;
  if (!preserveContext) setScreenLoading(inventoryScreen, true);
  inventoryStatus.textContent = t("ui.loadingInventory");
  if (!preserveContext) inventoryTableBody.replaceChildren(...inventorySkeletonRows());
  const storeId = document.querySelector("#inventory-store").value;
  try {
    const inventoryUrl = new URL(`${API_BASE_URL}/inventory`);
    inventoryUrl.searchParams.set("store_id", storeId);
    if (inventoryFilter) inventoryUrl.searchParams.set("inventory_filter", inventoryFilter);
    const [inventoryResponse, summaryResponse] = await Promise.all([
      fetch(inventoryUrl),
      inventorySummary(storeId)
    ]);
    if (!inventoryResponse.ok) throw new Error();
    inventoryEntries = (await inventoryResponse.json()).entries;
    renderInventorySummary(summaryResponse.summary);
    renderInventory();
    if (scrollTop !== null) catalogPanel.scrollTop = scrollTop;
    requestAnimationFrame(() => focusInventoryRow(focusProductId));
  } catch (error) {
    console.error(error);
    renderInventory();
    inventoryStatus.textContent = t("inventory.loadError");
  } finally {
    if (!preserveContext) setScreenLoading(inventoryScreen, false);
  }
}

function inventorySkeletonRows() {
  return Array.from({ length: 7 }, () => {
    const row = document.createElement("tr");
    row.className = "table-row skeleton-table-row";
    ["72%", "56%", "64%", "52%", "58%", "48%", "50%", "60%", "56%", "52%"].forEach((width, index) => {
      const cell = document.createElement("td");
      cell.className = "table-cell";
      cell.appendChild(skeletonBlock("skeleton-line", width));
      row.appendChild(cell);
    });
    return row;
  });
}
function orderIsClosed(order) { return ["received", "closed"].includes(order.status); }
function requestedLineCost(line) { return Number(line.product_cost || 0) * Number(line.quantity || 0); }
function lineCost(line, order) { const quantity = orderIsClosed(order) ? (line.quantity_observed ?? line.quantity) : line.quantity; return Number(line.product_cost || 0) * Number(quantity || 0); }
function lineCostDifference(line, order) { return orderIsClosed(order) ? lineCost(line, order) - requestedLineCost(line) : 0; }
function orderCost(order) { return order.lines.reduce((total, line) => total + lineCost(line, order), 0); }
function orderCostDifference(order) { return order.lines.reduce((total, line) => total + lineCostDifference(line, order), 0); }
function hasCountingDiscrepancy(order) { return orderIsClosed(order) && order.lines.some((line) => Number(line.quantity_observed ?? line.quantity) !== Number(line.quantity)); }
function renderOrderStatusSummary() { ordersSummary.replaceChildren(...Object.entries(purchaseOrderStatusCounts).map(([status, count]) => { const card = document.createElement("article"); card.className = "card inventory-summary-card"; const button = document.createElement("button"); button.className = "btn inventory-kpi"; button.type = "button"; button.dataset.orderStatus = status; button.dataset.variant = purchaseOrderStatusFilter === status ? "secondary" : "ghost"; button.setAttribute("aria-pressed", String(purchaseOrderStatusFilter === status)); button.setAttribute("aria-label", `${purchaseOrderStatusFilter === status ? t("ui.clear") : t("ui.apply")} ${status} ${t("ui.purchaseOrders").toLowerCase()}`); button.innerHTML = `<div class="card-header"><p class="card-title">${status}</p></div><div class="card-content"><p class="inventory-kpi-value numeric">${count}</p><p class="inventory-kpi-detail">${t("ui.purchaseOrders")}</p></div>`; button.addEventListener("click", () => { purchaseOrderStatusFilter = purchaseOrderStatusFilter === status ? "" : status; loadOrders(); }); card.appendChild(button); return card; })); }
function renderOrders() { const entries = sortOperationEntries(purchaseOrders, purchaseOrderSort); const labels = [t("ui.purchaseOrder"), t("ui.source"), t("ui.destinationStore"), t("ui.orderCost"), t("ui.costDifference"), t("ui.status"), t("ui.date"), t("ui.createdBy")]; ordersTableBody.replaceChildren(...entries.map((order) => { const closed = orderIsClosed(order); const discrepancy = hasCountingDiscrepancy(order); const row = document.createElement("tr"); row.className = `table-row purchase-order-row purchase-order-${closed ? "received" : "open"}`; const values = [`#${order.id}`, order.from_origin_name || "—", order.to_store_name || "—", currency(orderCost(order)), currency(orderCostDifference(order)), closed ? t("order.closed") : t("order.open"), order.date_opened, order.user_requester || "—"]; values.forEach((value, index) => { const cell = document.createElement("td"); cell.className = `table-cell${[3, 4].includes(index) ? " numeric" : ""}`; cell.dataset.label = labels[index]; if (index === 6) appendDateTime(cell, value); else cell.textContent = value; if (index === 5 && discrepancy) { const warning = document.createElement("span"); warning.className = "counting-warning"; warning.setAttribute("role", "img"); warning.setAttribute("aria-label", t("inventory.countingDiscrepancy")); warning.title = t("inventory.observedDiffers"); warning.textContent = "⚠"; cell.append(" ", warning); } row.appendChild(cell); }); const action = document.createElement("td"); action.className = "table-cell"; action.dataset.label = t("ui.actions"); action.innerHTML = `<button class="btn" type="button" data-variant="outline" data-size="sm" data-order-detail="${order.id}">${t("ui.view")}</button>`; row.appendChild(action); return row; })); ordersStatus.textContent = entries.length ? `${entries.length} ${t("ui.purchaseOrders").toLowerCase()}` : t("ui.purchaseOrdersLoadError"); }
async function loadOrders() { ordersStatus.textContent = t("ui.loadingPurchaseOrders"); try { const [orders, sources] = await Promise.all([productOrders(storeId, purchaseOrderStatusFilter), purchaseSources(storeId)]); purchaseOrders = orders.entries.map((order) => ({ ...order, last_updated: order.date_closed || order.date_opened })); purchaseOrderStatusCounts = orders.status_counts || {}; purchaseOrderSources = sources.entries; renderOrderStatusSummary(); renderOrders(); } catch { ordersStatus.textContent = t("ui.purchaseOrdersLoadError"); } }
function showOrderDetail(order) {
  document.querySelector("#purchase-order-title").dataset.storeTitleBase = "Purchase order";
  updateStoreTitles();
  selectedOrder = order;
  ordersScreen.hidden = true;
  purchaseOrderScreen.hidden = false;
  const position = purchaseOrders.findIndex((item) => item.id === order.id);
  const isOpen = order.status === "opened";
  const discrepancy = hasCountingDiscrepancy(order);
  const detail = document.querySelector("#order-detail");
  detail.innerHTML = `<div class="card-header"><div><p class="eyebrow">${t("order.number", { id: order.id })}</p><h3 class="card-title">${["received", "closed"].includes(order.status) ? t("order.closed") : t("order.open")}${discrepancy ? ` <span class="counting-warning" role="img" aria-label="${t("inventory.countingDiscrepancy")}" title="${t("inventory.observedDiffers")}">⚠</span>` : ""}</h3><p class="field-description">${order.from_origin_name || t("order.externalSource")} → ${order.to_store_name || "—"} · ${t("order.createdBy")} ${order.user_requester || "—"} · ${formatOperationDate(order.date_opened)}</p></div><div class="purchase-order-actions"><button class="btn" type="button" data-variant="outline" data-size="sm" data-order-navigation="previous" ${position <= 0 ? "disabled" : ""}>${t("order.previous")}</button><button class="btn" type="button" data-variant="outline" data-size="sm" data-order-navigation="next" ${position === purchaseOrders.length - 1 ? "disabled" : ""}>${t("order.next")}</button>${isOpen ? `<button id="count-order" class="btn" type="button" data-variant="default">${t("order.startCounting")}</button>` : ""}</div></div><div class="card-content"><div class="table-container purchase-order-lines-scroll"><table class="table purchase-order-lines-table"><caption class="table-caption">${t("order.products")}</caption><thead><tr class="table-row"><th class="table-head">${t("ui.product")}</th><th class="table-head">${t("ui.sku")}</th><th class="table-head">${t("ui.currentQuantity")}</th><th class="table-head">${t("order.requested")}</th><th class="table-head">${t("order.observed")}</th><th class="table-head">${t("order.itemCost")}</th><th class="table-head">${t("ui.costDifference")}</th><th class="table-head">${t("ui.status")}</th></tr></thead><tbody>${order.lines.map((line) => `<tr class="table-row"><td class="table-cell"><button class="btn" type="button" data-variant="link" data-order-product-edit="${line.product_id}">${line.product_name}</button></td><td class="table-cell">${line.product_code || "—"}</td><td class="table-cell numeric">${line.current_quantity ?? 0}</td><td class="table-cell numeric">${line.quantity}</td><td class="table-cell observed-cell"><input class="input numeric observed-input" type="number" inputmode="numeric" min="0" value="${line.quantity_observed ?? line.quantity}" aria-label="${t("order.observedQuantity", { name: line.product_name })}" data-observed-input data-line-id="${line.id}" disabled></td><td class="table-cell numeric">${currency(lineCost(line, order))}</td><td class="table-cell numeric">${currency(lineCostDifference(line, order))}</td><td class="table-cell">${line.status}</td></tr>`).join("")}</tbody><tfoot><tr class="purchase-order-total-row"><td colspan="5"></td><td class="numeric purchase-order-total-amount">${currency(orderCost(order))}</td><td class="numeric purchase-order-difference-amount">${currency(orderCostDifference(order))}</td><td></td></tr></tfoot></table></div></div>`;
  const observedInputs = [...detail.querySelectorAll("[data-observed-input]")];
  const countButton = detail.querySelector("#count-order");
  let counting = false;
  const focusObserved = (index) => { const input = observedInputs[Math.max(0, Math.min(index, observedInputs.length - 1))]; input?.scrollIntoView({ block: "center", behavior: "smooth" }); input?.focus({ preventScroll: true }); };
  observedInputs.forEach((input, index) => input.addEventListener("keydown", (event) => { if (!counting || !["Enter", "ArrowDown", "ArrowUp"].includes(event.key)) return; event.preventDefault(); focusObserved(index + (event.key === "ArrowUp" ? -1 : 1)); }));
  countButton?.addEventListener("click", async () => {
    if (!counting) { counting = true; observedInputs.forEach((input) => { input.disabled = false; }); countButton.textContent = t("order.process"); focusObserved(0); return; }
    const invalidInput = observedInputs.find((input) => !input.checkValidity());
    if (invalidInput) { invalidInput.focus(); invalidInput.reportValidity(); return; }
    countButton.disabled = true;
    countButton.textContent = t("order.processing");
    try {
      const processed = await receiveProductOrder(order.id, { lines: observedInputs.map((input) => ({ id: Number(input.dataset.lineId), quantity_observed: Number(input.value) })) });
      purchaseOrders = purchaseOrders.map((item) => item.id === processed.id ? processed : item);
      renderOrders();
      showOrderDetail(processed);
      loadInventory();
      refreshInventory(processed.lines.map((line) => line.product_id)).catch(console.error);
      window.toast?.success({ title: t("order.processed"), description: t("ui.inventory") });
    } catch (error) {
      countButton.disabled = false;
      countButton.textContent = t("order.process");
      window.toast?.error?.({ title: t("order.processError"), description: error.message });
    }
  });
  detail.querySelectorAll("[data-order-navigation]").forEach((button) => button.addEventListener("click", () => showOrderDetail(purchaseOrders[position + (button.dataset.orderNavigation === "previous" ? -1 : 1)])));
  detail.querySelectorAll("[data-order-product-edit]").forEach((button) => button.addEventListener("click", () => openProductEditor(Number(button.dataset.orderProductEdit), () => loadOrders().then(() => showOrderDetail(purchaseOrders.find((item) => item.id === order.id))))));
  requestAnimationFrame(() => document.querySelector("#purchase-order-title").focus());
}
function openPurchaseOrderCreate(mode = "purchase") { orderCreateMode = mode; ordersScreen.hidden = true; purchaseOrderScreen.hidden = false; const detail = document.querySelector("#order-detail"); const moving = mode === "move"; const sources = moving ? availableStores.map((store) => `<option value="${store.id}"${Number(store.id) === Number(storeId) ? " selected" : ""}>${store.name}</option>`).join("") : purchaseOrderSources.map((source) => `<option value="${source.id}">${source.name}</option>`).join(""); const destinations = availableStores.map((store) => `<option value="${store.id}"${Number(store.id) === Number(storeId) ? " selected" : ""}>${store.name}</option>`).join(""); document.querySelector("#purchase-order-title").textContent = moving ? t("order.moveProducts") : t("ui.purchaseOrder"); detail.innerHTML = `<div class="card-header"><div><p class="eyebrow">${t("ui.operations")}</p><h3 class="card-title">${moving ? t("order.moveProducts") : t("ui.createPurchaseOrder")}</h3><p class="field-description">${moving ? t("order.moveDescription") : t("order.createDescription")}</p></div></div><form id="purchase-order-create-form" class="form card-content"><div class="order-form-grid"><div class="form-field"><label class="label" for="purchase-order-source">${moving ? t("order.originStore") : t("order.sourceProvider")}</label><select id="purchase-order-source" class="select" required><option value="" disabled${moving ? "" : " selected"}>${moving ? t("order.selectOrigin") : t("order.selectSource")}</option>${sources}</select></div><div class="form-field"><label class="label" for="purchase-order-destination">${t("ui.destinationStore")}</label><select id="purchase-order-destination" class="select" required>${destinations}</select></div></div><div id="order-lines" class="order-lines"></div><button id="add-order-line" class="btn" type="button" data-variant="outline" data-size="sm">${t("product.add", { name: "" }).trim()}</button><p id="purchase-order-create-status" class="field-description" role="status"></p><div class="form-actions"><button class="btn" type="submit" data-variant="default">${moving ? t("order.moveProducts") : t("ui.createOrder")}</button></div></form>`; detail.querySelector("#add-order-line").addEventListener("click", () => addOrderLine(true)); const refreshLines = () => document.querySelectorAll("#order-lines .order-line[data-product-id]").forEach(refreshOrderLineInventoryQuantity); detail.querySelector("#purchase-order-source").addEventListener("change", refreshLines); if (!moving) detail.querySelector("#purchase-order-destination").addEventListener("change", refreshLines); detail.querySelector("form").addEventListener("submit", moving ? moveProducts : createPurchaseOrder); addOrderLine(true); requestAnimationFrame(() => document.querySelector("#purchase-order-source").focus()); }
async function createPurchaseOrder(event) { event.preventDefault(); const lines = orderLinesPayload(); const status = document.querySelector("#purchase-order-create-status"); if (!lines.length) { status.textContent = t("ui.addProductQuantity"); return; } status.textContent = t("ui.creating"); try { const order = await createProductOrder({ order_type: "purchase", from_origin_id: Number(document.querySelector("#purchase-order-source").value), to_store_id: Number(document.querySelector("#purchase-order-destination").value), lines }); purchaseOrders.unshift(order); renderOrders(); showOrderDetail(order); window.toast?.success({ title: t("order.created"), description: t("order.ready", { id: order.id }) }); } catch (error) { status.textContent = error.message; } }
async function moveProducts(event) { event.preventDefault(); const status = document.querySelector("#purchase-order-create-status"); const originStoreId = Number(document.querySelector("#purchase-order-source").value), destinationStoreId = Number(document.querySelector("#purchase-order-destination").value), lines = orderLinesPayload(); if (originStoreId === destinationStoreId) { status.textContent = t("order.differentStores"); return; } if (!lines.length) { status.textContent = t("ui.addProductQuantity"); return; } status.textContent = t("order.moving"); try { const result = await moveInventory({ from_origin_id: originStoreId, to_store_id: destinationStoreId, lines }); const productIds = result.product_ids || lines.map((line) => line.product_id); if (Number(storeId) === originStoreId || Number(storeId) === destinationStoreId) { await refreshInventory(productIds); if (!inventoryScreen.hidden) await loadInventory(); } window.toast?.success({ title: t("order.productsMoved"), description: t("order.inventoryUpdated") }); openOrders(); } catch (error) { status.textContent = error.message; } }
function fillProductOptions(select) { const entries = inventoryEntries.length ? inventoryEntries : products.map((product) => ({ product_id: product.id, product_name: product.name })); select.replaceChildren(...entries.map((e) => new Option(e.product_name, e.product_id))); }
function openProductDialog(onCreated = null) {
  pendingProductSelection = onCreated;
  pendingProductRefresh = null;
  createdProduct = null;
  editingProductId = null;
  const dialog = document.querySelector("#product-dialog");
  document.querySelector("#product-form").reset();
  preparedProductImage = null;
  imagePreparationTask = null;
  selectedProductImageFile = null;
  document.querySelector("#product-form button[type='submit']").disabled = false;
  document.querySelector("#product-image-help").textContent = "Drop an image here or choose a file (max 10 MB). It will be resized and stored as Base64.";
  setProductImagePreview(null);
  document.querySelector("#product-dialog-title").textContent = t("ui.createProduct");
  document.querySelector("#product-form-status").textContent = "";
  loadProductPricingFields();
  dialog.showModal();
  requestAnimationFrame(() => document.querySelector("#product-name").focus());
}
async function openProductEditor(productId, onSaved = null) {
  openProductDialog();
  pendingProductRefresh = onSaved;
  const status = document.querySelector("#product-form-status");
  status.textContent = t("ui.loading");
  try {
    const item = await product(productId);
    editingProductId = item.id;
    document.querySelector("#product-dialog-title").textContent = t("ui.edit") + " " + t("ui.product").toLowerCase();
    document.querySelector("#product-name").value = item.name || "";
    document.querySelector("#product-code").value = item.code || "";
    document.querySelector("#product-cost").value = item.cost ?? 0;
    setProductImagePreview(imageSource(item.image_raw));
    await loadProductPricingFields(item.prices || []);
    status.textContent = "";
  } catch (error) { status.textContent = error.message; }
}
function finishProductCreation() {
  document.querySelector("#product-dialog").close();
  pendingProductSelection = null;
  createdProduct = null;
}
async function loadProductPricingFields(existingPrices = []) {
  const fields = document.querySelector("#product-pricing-fields");
  fields.textContent = t("ui.loadingPricing");
  try {
    const { entries } = await pricingLists();
    const prices = new Map(existingPrices.map((entry) => [Number(entry.pricing_id), entry.price]));
    fields.replaceChildren(...entries.map((list) => {
      const row = document.createElement("div"); row.className = "product-price-row"; row.dataset.pricingId = list.id;
      const label = document.createElement("label"); label.className = "label"; label.htmlFor = `product-price-${list.id}`; label.textContent = list.label || `Pricing list #${list.id}`;
      const input = document.createElement("input"); input.id = label.htmlFor; input.className = "input"; input.type = "number"; input.min = "0"; input.step = "0.01"; input.placeholder = t("ui.price"); input.value = prices.get(Number(list.id)) ?? ""; input.required = Number(list.id) === 1; input.setAttribute("aria-label", t("ui.priceFor", { name: label.textContent }));
      row.append(label, input); return row;
    }));
    if (!entries.length) fields.textContent = t("ui.noPricing");
  } catch (error) { fields.textContent = error.message; }
}
function openInventoryDialog(productId) { const dialog = document.querySelector("#inventory-dialog"), select = document.querySelector("#inventory-product"); fillProductOptions(select); select.value = productId || inventoryEntries[0]?.product_id || ""; updateInventoryCurrent(); dialog.showModal(); }
function updateInventoryCurrent() { const entry = inventoryEntries.find((e) => String(e.product_id) === document.querySelector("#inventory-product").value); document.querySelector("#inventory-current").value = entry?.quantity ?? 0; }
function orderLineProducts() { return products.map((product) => ({ product_id: product.id, product_name: product.name, product_code: product.code, inventory_quantity: product.inventory_quantity })); }
function orderLineProductSearchText(entry) { return [entry.product_name, entry.product_code, entry.name, entry.code, entry.sku].filter(Boolean).join(" ").toLowerCase(); }
function orderLinesPayload() { return [...document.querySelectorAll("#order-lines .order-line")].map((line) => ({ product_id: Number(line.dataset.productId), quantity: Number(line.querySelector("input[type='number']").value) })).filter((line) => line.product_id > 0 && line.quantity > 0); }
async function refreshOrderLineInventoryQuantity(line) {
  const productId = Number(line.dataset.productId);
  const quantityStoreId = Number(orderCreateMode === "move" ? document.querySelector("#purchase-order-source")?.value : document.querySelector("#purchase-order-destination")?.value);
  const current = line.querySelector("[aria-label='Current inventory quantity']");
  if (!productId || !quantityStoreId || !current) return;
  current.value = "…";
  try {
    const { entries } = await inventoryQuantities(quantityStoreId, [productId]);
    const inventory = entries.find((entry) => Number(entry.product_id) === productId);
    if (Number(line.dataset.productId) === productId && Number(orderCreateMode === "move" ? document.querySelector("#purchase-order-source")?.value : document.querySelector("#purchase-order-destination")?.value) === quantityStoreId) current.value = inventory?.quantity ?? 0;
  } catch {
    if (Number(line.dataset.productId) === productId && Number(orderCreateMode === "move" ? document.querySelector("#purchase-order-source")?.value : document.querySelector("#purchase-order-destination")?.value) === quantityStoreId) current.value = "—";
  }
}
function addOrderLine(empty = true) { const line = document.createElement("div"); line.className = "order-line"; const edit = document.createElement("button"); edit.className = "btn"; edit.type = "button"; edit.dataset.variant = "outline"; edit.dataset.size = "icon-sm"; edit.setAttribute("aria-label", t("ui.editSelectedProduct")); edit.disabled = true; edit.textContent = "✎"; const picker = document.createElement("div"); picker.className = "product-combobox"; const product = document.createElement("input"); product.className = "input"; product.type = "text"; product.placeholder = t("ui.searchProducts"); product.autocomplete = "off"; product.spellcheck = false; product.setAttribute("autocorrect", "off"); product.setAttribute("autocapitalize", "off"); product.setAttribute("role", "combobox"); product.setAttribute("aria-label", t("ui.product")); product.setAttribute("aria-autocomplete", "list"); product.setAttribute("aria-expanded", "false"); const create = document.createElement("button"); create.className = "btn"; create.type = "button"; create.dataset.variant = "outline"; create.dataset.size = "icon-sm"; create.setAttribute("aria-label", t("ui.createProduct")); create.textContent = "+"; const results = document.createElement("ul"); results.className = "product-combobox-list"; results.id = `order-products-${uuid()}`; results.setAttribute("role", "listbox"); results.hidden = true; product.setAttribute("aria-controls", results.id); const current = document.createElement("input"); current.className = "input numeric"; current.type = "text"; current.readOnly = true; current.value = "—"; current.setAttribute("aria-label", t("ui.currentInventory")); const qty = document.createElement("input"); qty.className = "input"; qty.type = "number"; qty.min = "1"; qty.required = !empty; qty.setAttribute("aria-label", t("ui.requestedQuantity")); const remove = document.createElement("button"); remove.className = "btn"; remove.type = "button"; remove.dataset.variant = "ghost"; remove.dataset.size = "sm"; remove.textContent = t("ui.remove");
  let matches = [], activeIndex = -1, searchRequest = 0, candidates = orderLineProducts();
  const close = () => { searchRequest += 1; results.hidden = true; product.setAttribute("aria-expanded", "false"); activeIndex = -1; };
  const choose = async (entry) => {
    line.dataset.productId = entry.product_id;
    product.value = entry.product_code ? `${entry.product_name} · ${entry.product_code}` : entry.product_name;
    current.value = "…";
    edit.disabled = false; close(); qty.focus();
    refreshOrderLineInventoryQuantity(line);
  };
  const render = (entries = candidates) => { candidates = entries; const query = product.value.trim().toLowerCase(); matches = candidates.filter((entry) => orderLineProductSearchText(entry).includes(query)).slice(0, 50); if (activeIndex >= matches.length) activeIndex = matches.length - 1; results.replaceChildren(...matches.map((entry, index) => { const option = document.createElement("li"); option.id = `order-product-${uuid()}`; option.setAttribute("role", "option"); option.setAttribute("aria-selected", String(index === activeIndex)); option.textContent = entry.product_code ? `${entry.product_name} · ${entry.product_code}` : entry.product_name; option.addEventListener("mousedown", (event) => { event.preventDefault(); choose(entry); }); return option; })); results.hidden = matches.length === 0; product.setAttribute("aria-expanded", String(matches.length > 0)); product.setAttribute("aria-activedescendant", activeIndex >= 0 ? results.children[activeIndex]?.id || "" : ""); };
  const search = async () => { const query = product.value.trim(); const request = ++searchRequest; if (!query) { render(orderLineProducts()); return; } render(); try { const page = await activeProducts(storeId, null, query); if (request !== searchRequest || document.activeElement !== product) return; render(page.entries.map((entry) => ({ product_id: entry.id, product_name: entry.name, product_code: entry.code, inventory_quantity: entry.inventory_quantity }))); } catch { if (request === searchRequest && document.activeElement === product) render(); } };
  product.addEventListener("input", () => { delete line.dataset.productId; edit.disabled = true; activeIndex = -1; search(); }); product.addEventListener("focus", () => product.value.trim() ? search() : render(orderLineProducts())); product.addEventListener("keydown", (event) => { if (event.key === "ArrowDown" || event.key === "ArrowUp") { event.preventDefault(); if (!matches.length) render(); activeIndex = event.key === "ArrowUp" && activeIndex < 0 ? matches.length - 1 : Math.max(0, Math.min(matches.length - 1, activeIndex + (event.key === "ArrowDown" ? 1 : -1))); render(); } else if (event.key === "Home" && matches.length) { event.preventDefault(); activeIndex = 0; render(); } else if (event.key === "End" && matches.length) { event.preventDefault(); activeIndex = matches.length - 1; render(); } else if (event.key === "Enter" && matches.length) { event.preventDefault(); choose(matches[Math.max(activeIndex, 0)]); } else if (event.key === "Escape") close(); }); product.addEventListener("blur", () => setTimeout(close, 120));
  qty.addEventListener("keydown", (event) => { if (event.key !== "Enter") return; event.preventDefault(); if (!line.dataset.productId || !qty.validity.valid) return; addOrderLine(true); line.nextElementSibling?.querySelector("[role='combobox']")?.focus(); }); edit.addEventListener("click", () => openProductEditor(Number(line.dataset.productId), (updated) => { product.value = updated.code ? `${updated.name} · ${updated.code}` : updated.name; })); create.addEventListener("click", () => openProductDialog((newProduct) => choose({ product_id: newProduct.id, product_name: newProduct.name, product_code: newProduct.code, quantity: 0 }))); remove.addEventListener("click", () => line.remove()); picker.append(product, create, results); line.append(edit, picker, current, qty, remove); document.querySelector("#order-lines").appendChild(line); }
function openOrderDialog() { document.querySelector("#order-form").reset(); document.querySelector("#order-lines").replaceChildren(); addOrderLine(); document.querySelector("#order-dialog").showModal(); }
function openProcessOrder() { const lines = document.querySelector("#process-order-lines"); lines.replaceChildren(); selectedOrder.lines.forEach((line) => { const row = document.createElement("div"); row.className = "order-line process-line"; row.dataset.lineId = line.id; const name = document.createElement("span"); name.textContent = `${line.product_name} (requested ${line.quantity})`; const observed = document.createElement("input"); observed.className = "input"; observed.type = "number"; observed.min = "0"; observed.value = line.quantity_observed ?? line.quantity; row.append(name, observed); lines.appendChild(row); }); document.querySelector("#process-order-dialog").showModal(); }

function selectSidebar(id) {
  document.querySelectorAll(".sidebar-link").forEach((link) => {
    if (link.id === id) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  });
  const targetById = { "pos-nav": "pos", "sales-report-nav": "sales", "inventory-nav": "inventory", "orders-nav": "orders", "company-settings-nav": "company-settings", "users-nav": "users", "customers-nav": "customers", "settings-nav": "settings" };
  const target = targetById[id];
  document.querySelectorAll(".mobile-navigation-link[data-navigation-target]").forEach((link) => {
    link.toggleAttribute("aria-current", link.dataset.navigationTarget === target);
  });
}

function openPos(event) {
  event?.preventDefault();
  closeUsersPage();
  invoiceReport.hidden = true;
  customersScreen.hidden = true;
  customerDetailScreen.hidden = true;
  inventoryScreen.hidden = true;
  ordersScreen.hidden = true;
  purchaseOrderScreen.hidden = true;
  companySettingsScreen.hidden = true;
  positionCustomerPicker("customer");
  checkoutFlow.hidden = true;
  startCheckoutButton.hidden = false;
  delete catalogPanel.dataset.view;
  appShell.classList.remove("invoice-view");
  selectSidebar("pos-nav");
  productSearch.focus();
}

function openSettings() {
  openPos();
  selectSidebar("settings-nav");
  const switcher = document.querySelector("#language-switcher");
  switcher.open = true;
  switcher.querySelector("summary").focus();
}

function selectCustomer(customer) {
  if (!customer) return;
  selectedCustomer = customer;
  updateCustomerPicker();
  const choice = document.querySelector("#customer-picker");
  const details = document.querySelector("#customer-details");
  if (choice) choice.textContent = customer.name;
  if (details) { details.hidden = false; details.textContent = `${customer.name} · ${customer.celphone || ""} · ${customer.address || ""}`; }
  document.querySelector("#customer-continue").disabled = false;
  document.querySelector("#credit-toggle").disabled = false;
  closeCustomers();
}

function imageSource(raw) {
  if (!raw) return null;
  if (raw.startsWith("data:image/") || raw.startsWith("http://") || raw.startsWith("https://")) return raw;
  return `data:image/jpeg;base64,${raw}`;
}

function productCard(product) {
  const card = document.createElement("article");
  card.className = "card product";
  card.tabIndex = 0; card.setAttribute("role", "button");
  card.dataset.productId = product.id; card.dataset.name = product.name || t("product.unnamed");
  card.dataset.price = product.price || 0; card.dataset.sub = product.sub; card.dataset.tax = product.tax;
  card.setAttribute("aria-label", t("product.add", { name: product.name || t("product.unnamed") }));
  const source = imageSource(product.image_raw);
  if (source) {
    const image = document.createElement("img");
    image.className = "product-image"; image.src = source; image.alt = ""; image.loading = "lazy";
    card.appendChild(image);
  } else {
    const placeholder = document.createElement("div");
    placeholder.className = "product-image product-image-placeholder";
    placeholder.setAttribute("aria-hidden", "true");
    placeholder.textContent = (product.name || "?").slice(0, 1).toUpperCase();
    card.appendChild(placeholder);
  }
  const content = document.createElement("div");
  content.className = "card-content product-content";
  const name = document.createElement("h2");
  name.className = "card-title product-name"; name.textContent = product.name || t("product.unnamed");
  const meta = document.createElement("div");
  meta.className = "product-footer";
  const price = document.createElement("strong");
  price.className = "product-price numeric"; price.textContent = currency(product.price);
  const inventory = document.createElement("span");
  inventory.className = "inventory-badge numeric";
  inventory.classList.toggle("inventory-badge-low", Number(product.inventory_quantity || 0) <= 0);
  inventory.textContent = t("product.stock", { count: Number(product.inventory_quantity || 0) });
  const code = document.createElement("p");
  code.className = "product-code"; code.textContent = product.code ? `SKU ${product.code}` : t("product.tap");
  meta.append(price, inventory); content.append(name, code, meta); card.appendChild(content);
  return card;
}

function renderProducts() {
  if (loading && !products.length) {
    productGrid.replaceChildren(...productSkeletonCards());
    return;
  }
  const query = productSearch.value.trim().toLocaleLowerCase();
  const visible = query ? products.filter((p) => `${p.name || ""} ${p.code || ""}`.toLocaleLowerCase().includes(query)) : products;
  productGrid.replaceChildren(...visible.map(productCard));
  if (!visible.length && !loading) productStatus.textContent = query ? t("product.emptyMatch") : t("product.none");
}

function productSkeletonCards() {
  return Array.from({ length: 8 }, () => {
    const card = document.createElement("article");
    card.className = "card product product-skeleton-card";
    const image = document.createElement("div");
    image.className = "skeleton product-skeleton-image";
    image.setAttribute("aria-hidden", "true");
    const content = document.createElement("div");
    content.className = "card-content product-content";
    content.append(skeletonBlock("skeleton-line", "72%"), skeletonBlock("skeleton-line", "42%"), skeletonBlock("skeleton-line", "58%"));
    card.append(image, content);
    return card;
  });
}

async function loadProducts({ reset = false } = {}) {
  if (!storeId || loading || (!reset && !hasMore)) return;
  if (reset) { cursor = null; hasMore = true; products = []; }
  loading = true;
  renderProducts();
  productStatus.textContent = products.length ? t("product.loadingMore") : t("products.loading");
  try {
    const page = await activeProducts(storeId, cursor);
    products = products.concat(page.entries);
    cursor = page.next_cursor;
    hasMore = page.has_more;
    renderProducts();
    productStatus.textContent = hasMore ? t("product.scroll") : t("product.loaded", { count: products.length });
  } catch (error) {
    console.error(error);
    productStatus.textContent = t("product.error");
  } finally { loading = false; }
}

async function refreshInventory(productIds) {
  const ids = [...new Set(productIds.map(Number))].filter(Number.isInteger);
  if (!ids.length) return;
  const page = await inventoryQuantities(storeId, ids);
  const quantities = new Map(page.entries.map((entry) => [Number(entry.product_id), entry.quantity]));
  products = products.map((product) => quantities.has(Number(product.id)) ? { ...product, inventory_quantity: quantities.get(Number(product.id)) } : product);
  renderProducts();
  if (!inventoryScreen.hidden) {
    const { summary } = await inventorySummary(document.querySelector("#inventory-store").value);
    renderInventorySummary(summary);
  }
}

function subscribeToInventory() {
  inventorySocket?.close();
  const socketUrl = new URL(API_BASE_URL);
  socketUrl.protocol = socketUrl.protocol === "https:" ? "wss:" : "ws:";
  socketUrl.pathname = "/socket/websocket";
  socketUrl.search = `vsn=2.0.0&token=${encodeURIComponent(session()?.token || "")}`;
  const socket = inventorySocket = new WebSocket(socketUrl);

  socket.addEventListener("open", () => socket.send(JSON.stringify(["1", "1", `inventory:${session()?.user?.tenant}:${storeId}`, "phx_join", {}])));
  socket.addEventListener("message", (event) => {
    const [, , , name, payload] = JSON.parse(event.data);
    if (name === "inventory_changed") refreshInventory(payload.product_ids).catch(console.error);
  });
}

const isDesktopTauri = Boolean(window.__TAURI__) && !/Android|iPhone|iPad/i.test(navigator.userAgent);
const errorMessage = (error) => error instanceof Error ? error.message : String(error || "Printer failed.");
function renderPrintTargets() {
  const button = document.querySelector("#print-receipt"), field = document.querySelector("#print-target-field"), select = document.querySelector("#print-target");
  if (isDesktopTauri) { button.hidden = false; field.hidden = true; return; }
  button.hidden = !printTargets.length; field.hidden = printTargets.length < 2;
  select.replaceChildren(...printTargets.map((entry) => new Option(`${entry.label} · ${entry.printer}`, entry.session_id)));
  document.querySelector("#receipt-print-description").textContent = printTargets.length ? t("payment.choosePrinter") : t("ui.noDesktopPrinter");
}
function startPrintRelay() {
  printRelay?.close();
  clearInterval(printerAvailabilityTimer);
  printRelay = createPrintRelay({ device: isDesktopTauri ? "desktop" : "mobile", storeId, printerStatus: printer.status,
    onTargets: (targets) => { printTargets = targets; renderPrintTargets(); },
    onRequest: async ({ request_id, receipt }) => {
      if (printedRelayRequests.has(request_id)) return;
      printedRelayRequests.add(request_id);
      try { printRelay.reportResult({ request_id, status: "success", message: await printer.print(receipt) }); }
      catch (error) { printRelay.reportResult({ request_id, status: "failed", message: errorMessage(error) }); }
      finally { setTimeout(() => printedRelayRequests.delete(request_id), 300_000); printRelay.updatePrinter(); }
    },
    onResult: (result) => { clearTimeout(pendingPrintTimeout); const status = document.querySelector("#receipt-print-status"); status.textContent = result.status === "success" ? t("ui.receiptPrinted") : t("payment.printFailed", { error: result.message || t("payment.desktopUnavailable") }); if (result.status === "success") setTimeout(() => { document.querySelector("#receipt-dialog").close(); completedReceipt = null; }, 700); },
  });
  printRelay.connect();
  if (isDesktopTauri) {
    const publishPrinterAvailability = async () => {
      await updatePrinterStatus();
      await printRelay?.updatePrinter();
    };
    printerAvailabilityTimer = setInterval(publishPrinterAvailability, 5_000);
    publishPrinterAvailability();
    window.addEventListener("focus", publishPrinterAvailability);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) publishPrinterAvailability(); });
  }
}

async function updatePrinterStatus() {
  try {
    const status = await printer.status();
    const label = status.connected ? t("printer.connected") : t("printer.disconnected");
    printerStatus.setAttribute("aria-label", label);
    printerStatus.title = label;
    printerStatus.classList.toggle("connected", status.connected);
    printerStatus.classList.toggle("disconnected", !status.connected);
    return status.connected;
  } catch (error) {
    console.error(error);
    const label = t("printer.disconnected");
    printerStatus.setAttribute("aria-label", label);
    printerStatus.title = label;
    printerStatus.classList.remove("connected"); printerStatus.classList.add("disconnected"); return false;
  }
}

productSearch.addEventListener("input", () => { productSearchClear.hidden = !productSearch.value; renderProducts(); });
productSearch.addEventListener("search", () => { productSearchClear.hidden = !productSearch.value; renderProducts(); });
productSearch.addEventListener("keydown", (event) => { if (event.key === "Enter") renderProducts(); });
productSearchClear.addEventListener("click", () => { productSearch.value = ""; productSearchClear.hidden = true; renderProducts(); productSearch.focus(); });
orderTitle.addEventListener("click", () => {
  if (!checkoutFlow.hidden && checkoutStage === "payment") return;
  const returnTo = mobileQuery.matches && orderPanel.classList.contains("is-mobile-open") ? "cart" : "pos";
  if (returnTo === "cart") setMobileCart(false);
  openCustomers(returnTo);
});
clearCustomerButton.addEventListener("click", () => { if (!checkoutFlow.hidden && checkoutStage === "payment") return; selectedCustomer = null; updateCustomerPicker(); });
customerPurchasesButton.addEventListener("click", openCustomerPurchases);
document.querySelector("#customers-back").addEventListener("click", closeCustomers);
document.querySelector("#customer-detail-back").addEventListener("click", closeCustomerDetail);
document.querySelector("#customers-nav").addEventListener("click", () => openCustomers("standalone"));
customerSearch.addEventListener("input", () => { clearTimeout(customerSearchTimer); customerSearchTimer = setTimeout(loadCustomers, 220); });
document.querySelector("#pos-nav").addEventListener("click", openPos);
document.querySelector("#sales-report-nav").addEventListener("click", openInvoiceReport);
document.querySelector("#inventory-nav").addEventListener("click", openInventory);
document.querySelector("#orders-nav").addEventListener("click", openOrders);
document.querySelector("#company-settings-nav").addEventListener("click", openCompanySettings);
document.querySelector("#add-price-list").addEventListener("click", () => { editingCompanySetting = { kind: "price-list", id: "new" }; renderCompanySettings(); priceListsContent.querySelector("input")?.focus(); });
document.querySelector("#add-store").addEventListener("click", () => { editingCompanySetting = { kind: "store", id: "new" }; renderCompanySettings(); storesContent.querySelector("input")?.focus(); });
document.querySelector("#add-sequence-set").addEventListener("click", () => { editingCompanySetting = { kind: "sequence", id: "new" }; renderCompanySettings(); sequenceSetsContent.querySelector("input")?.focus(); });
document.querySelector("#add-provider").addEventListener("click", () => { editingCompanySetting = { kind: "provider", id: "new" }; renderCompanySettings(); providersContent.querySelector("input")?.focus(); });
[priceListsContent, storesContent, providersContent].forEach((container) => {
  container.addEventListener("click", async (event) => {
    if (event.target.closest("[data-company-setting-cancel]")) { editingCompanySetting = null; renderCompanySettings(); return; }
    if (event.target.closest("[data-remove-store-logo]")) { preparedStoreLogo = ""; selectedStoreLogoFile = null; setStoreLogoPreview(null); storesContent.querySelector(".store-logo-dropzone .field-description").textContent = "Logo will be removed when you save."; event.target.closest("[data-remove-store-logo]").remove(); return; }
    const button = event.target.closest("[data-company-setting-action]"); if (!button) return;
    const kind = button.dataset.kind; const id = Number(button.dataset.id);
    if (button.dataset.companySettingAction === "edit") { editingCompanySetting = { kind, id }; renderCompanySettings(); container.querySelector("input")?.focus(); return; }
    if (!confirm(`Delete this ${kind === "price-list" ? "price list" : kind}?`)) return;
    try { button.disabled = true; if (kind === "store") await deleteStore(id); else if (kind === "provider") await deleteProvider(id); else await deletePriceList(id); editingCompanySetting = null; await loadCompanySettings(); }
    catch (error) { companySettingsStatus.textContent = error.message; button.disabled = false; }
  });
  container.addEventListener("submit", async (event) => {
    event.preventDefault(); const form = event.target; if (!form.matches(".company-setting-form") || !form.reportValidity()) return;
    const kind = form.dataset.kind; const attrs = Object.fromEntries(new FormData(form)); const current = editingCompanySetting; const submit = form.querySelector('[type="submit"]');
    if (kind === "store") { if (storeLogoPreparationTask) await storeLogoPreparationTask; if (selectedStoreLogoFile && !preparedStoreLogo) { companySettingsStatus.textContent = "Choose a valid logo or remove it before saving."; return; } attrs.logo = preparedStoreLogo || ""; delete attrs["store-logo-file"]; }
    try { submit.disabled = true; if (kind === "store") current?.id === "new" ? await createStore(attrs) : await updateStore(current.id, attrs); else if (kind === "provider") current?.id === "new" ? await createProvider(attrs) : await updateProvider(current.id, attrs); else current?.id === "new" ? await createPriceList({ label: attrs.name }) : await updatePriceList(current.id, { label: attrs.name }); editingCompanySetting = null; await loadCompanySettings(); }
    catch (error) { companySettingsStatus.textContent = error.message; submit.disabled = false; }
  });
});
storesContent.addEventListener("change", (event) => { const input = event.target.closest(".store-logo-dropzone input[type='file']"); if (input) storeLogoPreparationTask = setStoreLogo(input.files?.[0]); });
storesContent.addEventListener("dragenter", (event) => { const dropzone = event.target.closest(".store-logo-dropzone"); if (dropzone) { event.preventDefault(); dropzone.dataset.dragging = "true"; } });
storesContent.addEventListener("dragover", (event) => { const dropzone = event.target.closest(".store-logo-dropzone"); if (dropzone) { event.preventDefault(); event.dataTransfer.dropEffect = "copy"; dropzone.dataset.dragging = "true"; } });
storesContent.addEventListener("dragleave", (event) => { const dropzone = event.target.closest(".store-logo-dropzone"); if (dropzone) delete dropzone.dataset.dragging; });
storesContent.addEventListener("drop", (event) => { const dropzone = event.target.closest(".store-logo-dropzone"); if (dropzone) { event.preventDefault(); delete dropzone.dataset.dragging; storeLogoPreparationTask = setStoreLogo(event.dataTransfer?.files?.[0]); } });
storesContent.addEventListener("keydown", (event) => { const dropzone = event.target.closest(".store-logo-dropzone"); if (dropzone && ["Enter", " "].includes(event.key)) { event.preventDefault(); dropzone.querySelector("input[type='file']").click(); } });
sequenceSetsContent.addEventListener("click", async (event) => {
  if (event.target.closest("[data-sequence-cancel]")) { editingCompanySetting = null; renderCompanySettings(); return; }
  const button = event.target.closest("[data-sequence-action]"); if (!button) return;
  const id = Number(button.dataset.id);
  if (button.dataset.sequenceAction === "edit") { editingCompanySetting = { kind: "sequence", id }; renderCompanySettings(); sequenceSetsContent.querySelector("input")?.focus(); return; }
  if (!confirm("Delete this sequence set?")) return;
  try { button.disabled = true; await deleteSequenceSet(id); editingCompanySetting = null; await loadCompanySettings(); } catch (error) { companySettingsStatus.textContent = error.message; button.disabled = false; }
});
sequenceSetsContent.addEventListener("submit", async (event) => {
  event.preventDefault(); const form = event.target; if (!form.matches(".company-setting-form") || !form.reportValidity()) return;
  const submit = form.querySelector('[type="submit"]'); const attrs = Object.fromEntries(new FormData(form)); ["fill", "increment_by", "current_seq"].forEach((key) => { attrs[key] = Number(attrs[key]); });
  try { submit.disabled = true; editingCompanySetting?.id === "new" ? await createSequenceSet(attrs) : await updateSequenceSet(editingCompanySetting.id, attrs); editingCompanySetting = null; await loadCompanySettings(); } catch (error) { companySettingsStatus.textContent = error.message; submit.disabled = false; }
});
document.querySelectorAll(".mobile-navigation-link[data-navigation-target]").forEach((item) => {
  item.addEventListener("click", () => {
    const actions = {
      pos: openPos,
      customers: () => openCustomers("standalone"),
      sales: openInvoiceReport,
      inventory: openInventory,
      orders: openOrders,
      "company-settings": openCompanySettings,
      users: openUsers,
      settings: openSettings,
    };
    closeMobileNavigation({ restoreFocus: false });
    actions[item.dataset.navigationTarget]?.();
  });
});
document.querySelector("#inventory-screen thead").addEventListener("click", (event) => { const button = event.target.closest("[data-inventory-sort]"); if (!button) return; const key = button.dataset.inventorySort; inventorySort = { key, direction: inventorySort.key === key && inventorySort.direction === "asc" ? "desc" : "asc" }; document.querySelectorAll("[data-inventory-sort]").forEach((item) => item.parentElement.setAttribute("aria-sort", item === button ? (inventorySort.direction === "asc" ? "ascending" : "descending") : "none")); renderInventory(); });
document.querySelector("#orders-screen thead").addEventListener("click", (event) => { const button = event.target.closest("[data-order-sort]"); if (!button) return; const key = button.dataset.orderSort; purchaseOrderSort = { key, direction: purchaseOrderSort.key === key && purchaseOrderSort.direction === "asc" ? "desc" : "asc" }; document.querySelectorAll("[data-order-sort]").forEach((item) => item.parentElement.setAttribute("aria-sort", item === button ? (purchaseOrderSort.direction === "asc" ? "ascending" : "descending") : "none")); renderOrders(); });
inventorySearchInput.addEventListener("input", renderInventory);
document.querySelector("#inventory-store").addEventListener("change", (event) => selectStore(event.currentTarget.value));
sidebarStoreMenu.addEventListener("click", (event) => {
  const button = event.target.closest("[data-store-id]");
  if (!button) return;
  sidebarStoreMenu.open = false;
  selectStore(button.dataset.storeId);
});
document.querySelector("#inventory-kpis-toggle").addEventListener("click", (event) => {
  const expanded = event.currentTarget.getAttribute("aria-expanded") !== "true";
  inventorySummaryGrid.classList.toggle("is-collapsed", !expanded);
  event.currentTarget.setAttribute("aria-expanded", String(expanded));
  event.currentTarget.innerHTML = `${expanded ? "Show fewer KPIs" : "Show more KPIs"} <span aria-hidden="true">${expanded ? "⌃" : "⌄"}</span>`;
});
inventorySummaryGrid.addEventListener("click", (event) => {
  const card = event.target.closest("[data-inventory-filter]");
  if (!card) return;
  inventoryFilter = inventoryFilter === card.dataset.inventoryFilter ? "" : card.dataset.inventoryFilter;
  loadInventory();
});
inventoryTableBody.addEventListener("click", async (event) => {
  const editProduct = event.target.closest("[data-edit-product]");
  if (editProduct) { openProductEditor(Number(editProduct.dataset.editProduct)); return; }
  const totalQuantity = event.target.closest("[data-total-quantity]");
  if (totalQuantity) {
    const productId = Number(totalQuantity.dataset.totalQuantity);
    if (expandedInventoryDetail?.productId === productId && expandedInventoryDetail.type === "quantity") { expandedInventoryDetail = null; expandedStoreQuantities = []; loadingStoreQuantitiesProductId = null; renderInventoryWithoutMoving(); return; }
    expandedInventoryDetail = { productId, type: "quantity" };
    expandedStoreQuantities = [];
    expandedProductTraces = [];
    loadingTraceProductId = null;
    loadingStoreQuantitiesProductId = productId;
    renderInventoryWithoutMoving();
    try {
      await new Promise(requestAnimationFrame);
      if (expandedInventoryDetail?.productId !== productId || expandedInventoryDetail.type !== "quantity" || loadingStoreQuantitiesProductId !== productId) return;
      expandedStoreQuantities = (await inventoryStoreQuantities(storeId, productId)).entries;
      if (expandedInventoryDetail?.productId !== productId || expandedInventoryDetail.type !== "quantity") return;
      loadingStoreQuantitiesProductId = null;
      renderInventoryWithoutMoving();
    } catch (error) {
      if (expandedInventoryDetail?.productId !== productId || expandedInventoryDetail.type !== "quantity") return;
      loadingStoreQuantitiesProductId = null;
      expandedInventoryDetail = null;
      expandedStoreQuantities = [];
      renderInventoryWithoutMoving();
      inventoryStatus.textContent = error.message;
    }
    return;
  }
  const traceTrigger = event.target.closest("[data-product-traces]");
  if (traceTrigger) {
    const productId = Number(traceTrigger.dataset.productTraces);
    if (expandedInventoryDetail?.productId === productId && expandedInventoryDetail.type === "trace") { expandedInventoryDetail = null; expandedProductTraces = []; loadingTraceProductId = null; renderInventoryWithoutMoving(); return; }
    expandedInventoryDetail = { productId, type: "trace" }; expandedProductTraces = []; expandedStoreQuantities = []; loadingStoreQuantitiesProductId = null; loadingTraceProductId = productId; renderInventoryWithoutMoving();
    try {
      await new Promise(requestAnimationFrame);
      if (expandedInventoryDetail?.productId !== productId || expandedInventoryDetail.type !== "trace" || loadingTraceProductId !== productId) return;
      expandedProductTraces = (await productTraces(storeId, productId)).entries;
      if (expandedInventoryDetail?.productId !== productId || expandedInventoryDetail.type !== "trace") return;
      loadingTraceProductId = null; renderInventoryWithoutMoving();
    } catch (error) {
      if (expandedInventoryDetail?.productId !== productId || expandedInventoryDetail.type !== "trace") return;
      loadingTraceProductId = null; expandedInventoryDetail = null; expandedProductTraces = []; renderInventoryWithoutMoving(); inventoryStatus.textContent = error.message;
    }
    return;
  }
  const update = event.target.closest("[data-adjust-product]");
  const cancel = event.target.closest("[data-cancel-inventory]");
  const save = event.target.closest("[data-save-inventory]");
  const saveStore = event.target.closest("[data-save-store-inventory]");
  if (update) { editingInventoryProductId = Number(update.dataset.adjustProduct); renderInventoryWithoutMoving(); requestAnimationFrame(() => document.querySelector(`#inventory-quantity-${editingInventoryProductId}`)?.focus()); return; }
  if (cancel) { editingInventoryProductId = null; renderInventoryWithoutMoving(); return; }
  if (saveStore) {
    const productId = Number(saveStore.dataset.saveStoreInventory);
    const targetStoreId = Number(saveStore.dataset.storeId);
    const input = document.querySelector(`#inventory-store-quantity-${productId}-${targetStoreId}`);
    const quantity = Number(input.value);
    const storeEntry = expandedStoreQuantities.find((item) => Number(item.store_id) === targetStoreId);
    const entry = inventoryEntries.find((item) => Number(item.product_id) === productId);
    if (!Number.isInteger(quantity) || !storeEntry || !entry) { input.focus(); return; }
    saveStore.disabled = true;
    try {
      const updated = await adjustInventory({ product_id: productId, store_id: targetStoreId, quantity: quantity - Number(storeEntry.quantity || 0) });
      expandedStoreQuantities = expandedStoreQuantities.map((item) => Number(item.store_id) === targetStoreId ? { ...item, ...updated } : item);
      const delta = Math.max(Number(updated.quantity), 0) - Math.max(Number(storeEntry.quantity || 0), 0);
      inventoryEntries = inventoryEntries.map((item) => Number(item.product_id) === productId ? { ...item, total_quantity: Number(item.total_quantity ?? item.quantity ?? 0) + delta, ...(targetStoreId === Number(storeId) ? { quantity: updated.quantity, prev_quantity: updated.prev_quantity, last_update: updated.last_update, user_updated: updated.user_updated } : {}) } : item);
      if (targetStoreId === Number(storeId)) { products = products.map((item) => Number(item.id) === productId ? { ...item, inventory_quantity: updated.quantity } : item); renderProducts(); }
      renderInventoryWithoutMoving();
      window.toast?.success({ title: "Inventory updated", description: "The store quantity was refreshed." });
    } catch (error) { saveStore.disabled = false; inventoryStatus.textContent = error.message; }
    return;
  }
  if (!save) return;
  const productId = Number(save.dataset.saveInventory);
  const input = document.querySelector(`#inventory-quantity-${productId}`);
  const quantity = Number(input.value);
  const entry = inventoryEntries.find((item) => Number(item.product_id) === productId);
  if (!Number.isInteger(quantity) || !entry) { input.focus(); return; }
  save.disabled = true;
  try {
    const updated = await adjustInventory({ product_id: productId, store_id: storeId, quantity: quantity - Number(entry.quantity || 0) });
    inventoryEntries = inventoryEntries.map((item) => Number(item.product_id) === productId ? { ...item, total_quantity: Number(item.total_quantity ?? item.quantity ?? 0) + (Number(updated.quantity) - Number(item.quantity || 0)), quantity: updated.quantity, prev_quantity: updated.prev_quantity, last_update: updated.last_update, user_updated: updated.user_updated } : item);
    products = products.map((item) => Number(item.id) === productId ? { ...item, inventory_quantity: updated.quantity } : item);
    editingInventoryProductId = null;
    renderProducts();
    renderInventoryWithoutMoving();
    window.toast?.success({ title: "Inventory updated", description: "The product quantity was refreshed." });
  } catch (error) {
    save.disabled = false;
    inventoryStatus.textContent = error.message;
  }
});
inventoryTableBody.addEventListener("keydown", (event) => {
  const storeInput = event.target.closest("[id^='inventory-store-quantity-']");
  if (storeInput && event.key === "Enter") { event.preventDefault(); storeInput.closest(".inventory-inline-editor")?.querySelector("[data-save-store-inventory]")?.click(); }
  const input = event.target.closest("[id^='inventory-quantity-']");
  if (input && event.key === "Enter") { event.preventDefault(); input.closest(".inventory-inline-editor")?.querySelector("[data-save-inventory]")?.click(); }
  if (input && event.key === "Escape") { editingInventoryProductId = null; renderInventoryWithoutMoving(); }
});
document.querySelector("#inventory-product").addEventListener("change", updateInventoryCurrent);
document.querySelector("#create-product").addEventListener("click", () => openProductDialog());
const productImageInput = document.querySelector("#product-image");
const productImageDropzone = document.querySelector("#product-image-dropzone");
const productImagePreview = document.createElement("img");
productImagePreview.className = "product-image-preview";
productImagePreview.alt = t("ui.productImagePreview");
productImagePreview.hidden = true;
productImageDropzone.prepend(productImagePreview);
function setProductImagePreview(source) {
  productImagePreview.hidden = !source;
  if (source) productImagePreview.src = source;
  else productImagePreview.removeAttribute("src");
}
const setProductImage = async (file) => {
  if (!file || !file.type.startsWith("image/")) return;
  const help = productImageDropzone.querySelector(".field-description");
  if (file.size > MAX_PRODUCT_IMAGE_BYTES) {
    productImageInput.value = "";
    preparedProductImage = null;
    selectedProductImageFile = null;
    setProductImagePreview(null);
    help.textContent = t("ui.imageTooLarge");
    return;
  }
  selectedProductImageFile = file;
  help.textContent = t("ui.resizingImage");
  try {
    const source = new Image();
    const objectUrl = URL.createObjectURL(file);
    source.src = objectUrl;
    await source.decode();
    const width = 100;
    const height = Math.max(1, Math.round(source.naturalHeight * (width / source.naturalWidth)));
    const canvas = document.createElement("canvas"); canvas.width = width; canvas.height = height;
    await imageResizer.resize(source, canvas);
    const blob = await imageResizer.toBlob(canvas, "image/jpeg", 0.82);
    URL.revokeObjectURL(objectUrl);
    preparedProductImage = await new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.onerror = reject; reader.readAsDataURL(blob); });
    setProductImagePreview(preparedProductImage);
    help.textContent = `${file.name} resized to ${width} × ${height}px and ready as Base64.`;
  } catch (error) { preparedProductImage = null; help.textContent = `Image could not be prepared: ${error.message}`; }
};
function imageMimeType(name) {
  const extension = name.split(".").pop()?.toLowerCase();
  return ({ jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", gif: "image/gif", bmp: "image/bmp" })[extension] || "application/octet-stream";
}
function setStoreLogoPreview(source) {
  const preview = storesContent.querySelector(".store-logo-preview");
  if (!preview) return;
  preview.hidden = !source;
  if (source) preview.src = source;
  else preview.removeAttribute("src");
}
async function setStoreLogo(file) {
  const dropzone = storesContent.querySelector(".store-logo-dropzone");
  if (!dropzone || !file || !file.type.startsWith("image/")) return;
  const help = dropzone.querySelector(".field-description");
  if (file.size > MAX_PRODUCT_IMAGE_BYTES) { selectedStoreLogoFile = null; preparedStoreLogo = null; setStoreLogoPreview(null); help.textContent = t("ui.imageTooLarge"); return; }
  selectedStoreLogoFile = file;
  help.textContent = t("ui.resizingImage");
  try {
    const source = new Image(), objectUrl = URL.createObjectURL(file); source.src = objectUrl; await source.decode();
    const width = 100, height = Math.max(1, Math.round(source.naturalHeight * (width / source.naturalWidth)));
    const canvas = document.createElement("canvas"); canvas.width = width; canvas.height = height;
    await imageResizer.resize(source, canvas); const blob = await imageResizer.toBlob(canvas, "image/jpeg", 0.82); URL.revokeObjectURL(objectUrl);
    preparedStoreLogo = await new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.onerror = reject; reader.readAsDataURL(blob); });
    setStoreLogoPreview(preparedStoreLogo); help.textContent = `${file.name} resized to ${width} × ${height}px and ready as Base64.`;
  } catch (error) { preparedStoreLogo = null; help.textContent = `Image could not be prepared: ${error.message}`; }
}
productImageDropzone.addEventListener("dragenter", (event) => { event.preventDefault(); event.stopPropagation(); productImageDropzone.dataset.dragging = "true"; });
productImageDropzone.addEventListener("dragover", (event) => { event.preventDefault(); event.stopPropagation(); event.dataTransfer.dropEffect = "copy"; productImageDropzone.dataset.dragging = "true"; });
productImageDropzone.addEventListener("dragleave", (event) => { event.preventDefault(); delete productImageDropzone.dataset.dragging; });
productImageDropzone.addEventListener("drop", (event) => { event.preventDefault(); event.stopPropagation(); delete productImageDropzone.dataset.dragging; const file = event.dataTransfer?.files?.[0]; const help = productImageDropzone.querySelector(".field-description"); if (!file) { help.textContent = "Drop an image file here."; return; } imagePreparationTask = setProductImage(file); });
productImageDropzone.addEventListener("keydown", (event) => { if (["Enter", " "].includes(event.key)) { event.preventDefault(); productImageInput.click(); } });
productImageInput.addEventListener("change", () => { imagePreparationTask = setProductImage(productImageInput.files[0]); });
window.addEventListener("dragover", (event) => { if (document.querySelector("#product-dialog").open) event.preventDefault(); });
window.addEventListener("drop", (event) => { if (document.querySelector("#product-dialog").open) event.preventDefault(); });
window.__TAURI__?.webview?.getCurrentWebview?.().onDragDropEvent(async ({ payload }) => {
  const dialog = document.querySelector("#product-dialog");
  const storeDropzone = storesContent.querySelector(".store-logo-dropzone");
  if (!dialog.open && !storeDropzone) return;
  const dropzone = dialog.open ? productImageDropzone : storeDropzone;
  if (payload.type === "over") { dropzone.dataset.dragging = "true"; return; }
  if (payload.type === "leave") { delete dropzone.dataset.dragging; return; }
  if (payload.type !== "drop" || !payload.paths?.[0]) return;
  delete dropzone.dataset.dragging;
  const help = dropzone.querySelector(".field-description");
  help.textContent = t("ui.readingImage");
  try {
    const bytes = await window.__TAURI__.core.invoke("read_dropped_image", { path: payload.paths[0] });
    const name = String(payload.paths[0]).split(/[\\/]/).pop() || "dropped-image";
    const file = new File([new Uint8Array(bytes)], name, { type: imageMimeType(name) });
    if (dialog.open) imagePreparationTask = setProductImage(file);
    else storeLogoPreparationTask = setStoreLogo(file);
  } catch (error) { help.textContent = `Image could not be read: ${error}`; }
});
document.querySelector("#product-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.currentTarget, status = document.querySelector("#product-form-status"), file = selectedProductImageFile;
  if (imagePreparationTask) await imagePreparationTask;
  if (file && !preparedProductImage) { status.textContent = "Choose a valid image or remove it before saving."; return; }
  const imageRaw = preparedProductImage || "";
  const prices = [...form.querySelectorAll("[data-pricing-id]")].map((row) => ({ pricing_id: Number(row.dataset.pricingId), price: row.querySelector("input").value })).filter((entry) => entry.price !== "");
  const product = { store_id: document.querySelector("#inventory-store").value, name: document.querySelector("#product-name").value.trim(), code: document.querySelector("#product-code").value.trim(), cost: Number(document.querySelector("#product-cost").value || 0), image_raw: imageRaw };
  if (!file && editingProductId) delete product.image_raw;
  status.textContent = editingProductId || createdProduct ? "Saving…" : "Creating…"; form.querySelector("button[type='submit']").disabled = true;
  try {
    if (editingProductId) {
      createdProduct = await updateProduct(editingProductId, product);
    } else if (!createdProduct) {
      createdProduct = await createProduct({ ...product, prices });
      products = [createdProduct, ...products.filter((item) => Number(item.id) !== Number(createdProduct.id))];
      inventoryEntries.unshift({ product_id: createdProduct.id, product_name: createdProduct.name, product_code: createdProduct.code, product_cost: createdProduct.cost, product_price: createdProduct.price, store_name: "Current store", quantity: createdProduct.inventory_quantity, prev_quantity: 0 });
      pendingProductSelection?.(createdProduct); renderInventory();
    }
    if (editingProductId && prices.length) await setProductPrices(createdProduct.id, prices);
    await loadInventory(createdProduct.id);
    if (editingProductId) {
      products = products.map((item) => item.id === createdProduct.id ? { ...item, ...createdProduct } : item);
      pendingProductRefresh?.(createdProduct);
      window.toast?.success({ title: "Product updated", description: "Product details were refreshed." });
    } else window.toast?.success({ title: "Product created", description: prices.length ? "Product and pricing-list entries were saved." : "Product was created without selling prices." });
    finishProductCreation();
  } catch (error) { status.textContent = createdProduct ? `Product created. ${error.message}` : error.message; form.querySelector("button[type='submit']").disabled = false; }
});
document.querySelector("#inventory-form").addEventListener("submit", async (event) => { event.preventDefault(); const form = event.currentTarget; const productId = Number(document.querySelector("#inventory-product").value); const targetStoreId = Number(document.querySelector("#inventory-form-store").value); const quantity = Number(document.querySelector("#inventory-quantity").value); if (!Number.isInteger(quantity)) return; const status = document.querySelector("#inventory-form-status"); status.textContent = "Saving…"; try { const updated = await adjustInventory({ product_id: productId, store_id: targetStoreId, quantity }); const entry = inventoryEntries.find((item) => Number(item.product_id) === productId); const previous = targetStoreId === Number(storeId) ? Number(entry?.quantity || 0) : Number(expandedStoreQuantities.find((item) => Number(item.store_id) === targetStoreId)?.quantity || 0); const delta = Number(updated.quantity) - previous; inventoryEntries = inventoryEntries.map((item) => Number(item.product_id) === productId ? { ...item, total_quantity: Number(item.total_quantity ?? item.quantity ?? 0) + delta, ...(targetStoreId === Number(storeId) ? { quantity: updated.quantity, prev_quantity: updated.prev_quantity, last_update: updated.last_update, user_updated: updated.user_updated } : {}) } : item); expandedStoreQuantities = expandedStoreQuantities.map((item) => Number(item.store_id) === targetStoreId ? { ...item, ...updated } : item); if (targetStoreId === Number(storeId)) { products = products.map((item) => Number(item.id) === productId ? { ...item, inventory_quantity: updated.quantity } : item); renderProducts(); } document.querySelector("#inventory-dialog").close(); renderInventoryWithoutMoving(); window.toast?.success({ title: "Inventory updated", description: "The product quantity was refreshed." }); } catch (error) { status.textContent = error.message; } });
document.querySelector("#create-order").addEventListener("click", openPurchaseOrderCreate);
document.querySelector("#move-products").addEventListener("click", () => openPurchaseOrderCreate("move"));
document.querySelector("#purchase-order-back").addEventListener("click", () => { purchaseOrderScreen.hidden = true; ordersScreen.hidden = false; requestAnimationFrame(() => document.querySelector("#orders-title").focus()); });
document.querySelector("#add-order-line").addEventListener("click", addOrderLine);
document.querySelector("#order-form").addEventListener("submit", async (event) => { event.preventDefault(); const lines = [...document.querySelectorAll("#order-lines .order-line")].map((line) => ({ product_id: Number(line.querySelector("select").value), quantity: Number(line.querySelector("input[type='number']").value) })); const status = document.querySelector("#order-form-status"); status.textContent = "Creating…"; try { const order = await createProductOrder({ order_type: "purchase", from_origin_id: Number(document.querySelector("#order-source").value), to_store_id: Number(document.querySelector("#order-destination").value), lines }); document.querySelector("#order-dialog").close(); purchaseOrders.unshift(order); renderOrders(); showOrderDetail(order); window.toast?.success({ title: "Purchase order created", description: `Order #${order.id} is ready to process.` }); } catch (error) { status.textContent = error.message; } });
ordersTableBody.addEventListener("click", (event) => { const button = event.target.closest("[data-order-detail]"); if (button) showOrderDetail(purchaseOrders.find((order) => String(order.id) === button.dataset.orderDetail)); });
ordersTableBody.addEventListener("click", (event) => {
  if (event.target.closest("button, input")) return;
  event.target.closest(".purchase-order-row")?.querySelector("[data-order-detail]")?.click();
});
document.querySelector("#process-order-form").addEventListener("submit", async (event) => { event.preventDefault(); const status = document.querySelector("#process-order-status"); status.textContent = "Processing…"; try { const order = await receiveProductOrder(selectedOrder.id, { lines: [...document.querySelectorAll(".process-line")].map((row) => ({ id: Number(row.dataset.lineId), quantity_observed: Number(row.querySelector("input").value) })) }); document.querySelector("#process-order-dialog").close(); purchaseOrders = purchaseOrders.map((item) => item.id === order.id ? order : item); renderOrders(); showOrderDetail(order); loadInventory(); refreshInventory(order.lines.map((line) => line.product_id)).catch(console.error); window.toast?.success({ title: "Order processed", description: "Inventory quantities were refreshed." }); } catch (error) { status.textContent = error.message; } });
document.querySelector(".invoice-table thead").addEventListener("click", (event) => {
  const button = event.target.closest("[data-sort]");
  if (!button) return;
  const key = button.dataset.sort;
  invoiceSort = {
    key,
    direction: invoiceSort.key === key && invoiceSort.direction === "asc" ? "desc" : "asc"
  };
  document.querySelectorAll(".invoice-sort").forEach((sortButton) => {
    const active = sortButton === button;
    sortButton.parentElement.setAttribute("aria-sort", active ? (invoiceSort.direction === "asc" ? "ascending" : "descending") : "none");
  });
  sortInvoices();
  renderInvoices();
});
document.querySelectorAll("[data-status-filter]").forEach((button) => {
  button.setAttribute("aria-pressed", "false");
  button.addEventListener("click", () => {
    invoiceStatusFilter = invoiceStatusFilter === button.dataset.statusFilter ? "" : button.dataset.statusFilter;
    document.querySelectorAll("[data-status-filter]").forEach((kpi) => {
      const selected = kpi.dataset.statusFilter === invoiceStatusFilter;
      kpi.setAttribute("aria-pressed", String(selected));
      kpi.dataset.variant = selected ? "secondary" : "ghost";
    });
    loadInvoices({ reset: true });
  });
});
invoiceSearch.addEventListener("input", () => {
  clearTimeout(invoiceSearchTimer);
  invoiceSearchTimer = setTimeout(() => loadInvoices({ reset: true }), 250);
});
invoiceFilters.addEventListener("submit", (event) => {
  event.preventDefault();
  loadInvoices({ reset: true });
});
invoiceDateRangeTrigger.addEventListener("click", openDateRangePicker);
document.querySelector("#calendar-previous-month").addEventListener("click", () => { calendarMonth = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() - 1, 1); renderCalendar(); });
document.querySelector("#calendar-next-month").addEventListener("click", () => { calendarMonth = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() + 1, 1); renderCalendar(); });
invoiceCalendarGrid.addEventListener("click", (event) => {
  const day = event.target.closest("[data-date]");
  if (!day) return;
  const value = day.dataset.date;
  if (!calendarRange.from || calendarRange.to) calendarRange = { from: value, to: "" };
  else calendarRange = value < calendarRange.from ? { from: value, to: calendarRange.from } : { from: calendarRange.from, to: value };
  renderCalendar();
});
document.querySelector("#invoice-date-range-clear").addEventListener("click", () => { calendarRange = { from: "", to: "" }; renderCalendar(); });
document.querySelector("#invoice-date-range-apply").addEventListener("click", () => {
  invoiceDateFrom.value = calendarRange.from;
  invoiceDateTo.value = calendarRange.to;
  invoiceDateRangeTrigger.textContent = rangeLabel(calendarRange.from, calendarRange.to);
  invoiceDateRangeDialog.close();
  loadInvoices({ reset: true });
});
document.querySelector("#invoice-filters-clear").addEventListener("click", () => {
  invoiceFilters.reset();
  invoiceDateRangeTrigger.textContent = t("ui.anyDate");
  invoiceStatusFilter = "";
  document.querySelectorAll("[data-status-filter]").forEach((kpi) => { kpi.setAttribute("aria-pressed", "false"); kpi.dataset.variant = "ghost"; });
  loadInvoices({ reset: true });
});
invoiceTableBody.addEventListener("click", async (event) => {
  const paymentPrint = event.target.closest("[data-print-payment]");
  if (paymentPrint) {
    const invoice = invoiceDetails.get(Number(paymentPrint.dataset.invoiceId));
    const payment = invoice?.payments?.find((entry) => String(entry.id) === paymentPrint.dataset.printPayment);
    if (invoice && payment) openPaymentReceiptPrint(invoice, payment);
    return;
  }
  const print = event.target.closest("[data-print-invoice]");
  if (print) {
    const invoice = invoiceDetails.get(Number(print.dataset.printInvoice));
    if (invoice) openReceiptPrint(invoice);
    return;
  }
  const trigger = event.target.closest("[data-invoice-detail]");
  if (!trigger) return;
  const invoiceId = Number(trigger.dataset.invoiceDetail);
  if (expandedInvoiceId === invoiceId) {
    expandedInvoiceId = null;
    renderInvoices();
    return;
  }
  expandedInvoiceId = invoiceId;
  renderInvoices();
  if (invoiceDetails.has(invoiceId)) return;
  try {
    invoiceDetails.set(invoiceId, await saleDetails(invoiceId));
    if (expandedInvoiceId === invoiceId) renderInvoices();
  } catch (error) {
    console.error(error);
    expandedInvoiceId = null;
    renderInvoices();
    window.toast?.error({ title: "Could not load invoice details", description: error.message });
  }
});
invoiceTableBody.addEventListener("click", (event) => {
  if (event.target.closest("button, input, form")) return;
  event.target.closest(".invoice-row")?.querySelector("[data-invoice-detail]")?.click();
});
invoiceTableBody.addEventListener("click", (event) => {
  const button = event.target.closest("[data-payment-type]");
  if (!button || !button.closest(".invoice-payment-methods")) return;
  const row = button.closest(".invoice-payment-row");
  row.dataset.paymentType = button.dataset.paymentType;
  row.querySelectorAll("[data-payment-type]").forEach((method) => {
    const selected = method === button;
    method.dataset.variant = selected ? "default" : "secondary";
    method.setAttribute("aria-pressed", String(selected));
  });
});
invoiceTableBody.addEventListener("submit", async (event) => {
  const form = event.target.closest(".invoice-payment");
  if (!form) return;
  event.preventDefault();
  const invoice = invoices.find((entry) => String(entry.id) === form.dataset.invoiceId);
  const submit = event.submitter;
  const paymentRow = submit?.closest(".invoice-payment-row");
  const isPayoff = paymentRow?.classList.contains("invoice-payment-payoff");
  const amount = isPayoff ? Number(invoice?.due_balance) : Number(paymentRow?.querySelector("input[name='paymentAmount']")?.value);
  if (!invoice || !Number.isFinite(amount) || amount <= 0 || amount > Number(invoice.due_balance)) return;
  submit.disabled = true;
  try {
    const sale = await addSalePayment(invoice.id, { amount, type: paymentRow.dataset.paymentType });
    const refreshedInvoice = { ...invoice, ...sale };
    invoices = invoices.map((entry) => entry.id === invoice.id ? refreshedInvoice : entry);
    invoiceDetails.set(invoice.id, refreshedInvoice);
    renderInvoicesPreservingScroll(refreshedInvoice.id);
    invoiceReportStatus.textContent = t("ui.paymentRecorded");
    window.toast?.success({ title: t("ui.paymentRecorded"), description: t("payment.applied", { amount: currency(amount), invoice: refreshedInvoice.sequence || refreshedInvoice.id }) });
  } catch (error) {
    console.error(error);
    invoiceReportStatus.textContent = error.message;
    window.toast?.error({ title: t("payment.recordError"), description: error.message });
    submit.disabled = false;
  }
});
invoiceTableBody.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-cancel-invoice]");
  if (!button) return;
  const invoice = invoices.find((entry) => String(entry.id) === button.dataset.cancelInvoice);
  if (!invoice) return;
  invoicePendingCancellation = invoice.id;
  document.querySelector("#invoice-cancel-details-title").textContent = invoice.sequence || `Invoice #${invoice.id}`;
  document.querySelector("#invoice-cancel-details").textContent = `${invoice.client_name || "Walk-in customer"} · ${currency(invoice.amount)} · ${invoice.date_create ? new Date(invoice.date_create.replace(" ", "T")).toLocaleDateString() : "No date"}`;
  invoiceCancelDialog.showModal();
});
document.querySelector("#confirm-invoice-cancel").addEventListener("click", async () => {
  const invoice = invoices.find((entry) => entry.id === invoicePendingCancellation);
  if (!invoice) return;
  const confirm = document.querySelector("#confirm-invoice-cancel");
  confirm.disabled = true;
  try {
    const sale = await cancelSale(invoice.id);
    Object.assign(invoice, sale);
    invoiceDetails.set(invoice.id, sale);
    renderInvoices();
    invoiceReportStatus.textContent = "Invoice cancelled.";
    invoiceCancelDialog.close();
    window.toast?.success({ title: "Invoice cancelled", description: `Inventory for invoice ${invoice.sequence || invoice.id} was restored.` });
  } catch (error) {
    console.error(error);
    invoiceReportStatus.textContent = error.message;
    window.toast?.error({ title: "Could not cancel invoice", description: error.message });
  } finally { confirm.disabled = false; invoicePendingCancellation = null; }
});
customerForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!customerForm.reportValidity()) return;
  const submit = document.querySelector("#customer-submit");
  customerFormStatus.hidden = true; submit.disabled = true;
  try {
    const attrs = Object.fromEntries(new FormData(customerForm));
    attrs.is_wholesaler = customerForm.elements.is_wholesaler.checked;
    const customer = await createCustomer(attrs);
    customerForm.reset(); customerDialog.close();
    if (!customersScreen.hidden) { loadCustomers(); openCustomerDetail(customer.id); } else selectCustomer(customer);
  } catch (error) {
    console.error(error); customerFormStatus.textContent = t("customer.saveError"); customerFormStatus.hidden = false;
  } finally { submit.disabled = false; }
});
document.querySelector("#search-focus").addEventListener("click", () => productSearch.focus());
productGrid.addEventListener("keydown", (event) => {
  const product = event.target.closest("[data-product-id]");
  if (product && (event.key === "Enter" || event.key === " ")) {
    event.preventDefault();
    product.click();
  }
});
new IntersectionObserver((entries) => { if (entries.some((entry) => entry.isIntersecting)) loadProducts(); }, { rootMargin: "360px" }).observe(productSentinel);
new IntersectionObserver((entries) => {
  if (!invoiceReport.hidden && entries.some((entry) => entry.isIntersecting)) loadInvoices();
}, { root: catalogPanel, rootMargin: "360px" }).observe(invoiceSentinel);
function showCheckoutStage(stage) {
  checkoutStage = stage;
  checkoutFlow.querySelectorAll("[data-stage]").forEach((element) => {
    element.hidden = element.dataset.stage !== stage;
  });
  checkoutFlow.querySelectorAll("[data-checkout-step]").forEach((element) => {
    const active = element.dataset.checkoutStep === stage;
    if (active) element.setAttribute("aria-current", "step");
    else element.removeAttribute("aria-current");
  });
  positionCustomerPicker(stage);
  const title = checkoutFlow.querySelector(`[data-stage="${stage}"] h2`)?.textContent;
  const checkoutTitle = document.querySelector("#checkout-title");
  checkoutTitle.dataset.storeTitleBase = title || "Checkout";
  updateStoreTitles();
  document.querySelector("#checkout-total").textContent = currency(pos.total());
  if (stage === "payment") updatePaymentCompletion();
  checkoutStatus.textContent = "";
  requestAnimationFrame(() => checkoutFlow.querySelector(`[data-stage="${stage}"] h2`)?.focus?.());
}

function positionCustomerPicker(stage) {
  const paymentReadOnly = stage === "payment";
  orderTitle.disabled = paymentReadOnly;
  clearCustomerButton.disabled = paymentReadOnly;
}

async function openCheckout() {
  if (pos.isEmpty()) { printStatus.textContent = t("print.addItem"); return; }
  if (checkoutOpening) return;
  checkoutOpening = true;
  if (mobileQuery.matches && orderPanel.classList.contains("is-mobile-open")) {
    setMobileCart(false, { restoreFocus: false });
    await new Promise((resolve) => window.setTimeout(resolve, 220));
  }
  catalogPanel.dataset.view = "checkout";
  startCheckoutButton.hidden = true;
  checkoutFlow.hidden = false;
  showCheckoutStage(selectedCustomer ? "payment" : "customer");
  requestAnimationFrame(() => {
    const focusTarget = selectedCustomer ? document.querySelector("#add-payment-line") : document.querySelector("#customer-picker");
    focusTarget?.focus();
    checkoutOpening = false;
  });
}

function closeCheckout() {
  positionCustomerPicker("customer");
  checkoutFlow.hidden = true;
  delete catalogPanel.dataset.view;
  startCheckoutButton.hidden = false;
  startCheckoutButton.focus();
}

function updatePaymentCompletion() {
  const saleTotal = pos.total();
  const paymentLines = [...document.querySelectorAll(".payment-line")];
  const paid = paymentLines.reduce((sum, line) => sum + (Number(line.querySelector("input").value) || 0), 0);
  const remaining = Math.max(0, saleTotal - paid);
  const change = Math.max(0, paid - saleTotal);
  document.querySelector("#checkout-total").textContent = currency(saleTotal);
  document.querySelector("#payment-balance").textContent = `${t("checkout.remaining")}: ${currency(remaining)}`;
  const changeLabel = document.querySelector("#payment-change");
  changeLabel.hidden = change === 0;
  changeLabel.textContent = change ? `${t("checkout.change")}: ${currency(change)}` : "";
  const onCredit = document.querySelector("#credit-toggle").getAttribute("aria-pressed") === "true";
  document.querySelector("#complete-sale").disabled = pos.isEmpty() || (!onCredit && paid < saleTotal);
}

function paymentAmount(input) {
  return Number(input?.value) || 0;
}

function roundPaymentAmount(amount) {
  return Math.round((amount + Number.EPSILON) * 100) / 100;
}

function paymentLineId() {
  return `payment-line-${uuid()}`;
}

function addPaymentLine() {
  const paymentLines = document.querySelector("#payment-lines");
  const previousLine = paymentLines.querySelector(".payment-line:last-child");
  const previous = previousLine?.querySelector("select")?.value;
  const method = previous === "CC" ? "CASH" : "CC";
  const paid = [...paymentLines.querySelectorAll(".payment-line input")].reduce((sum, input) => sum + paymentAmount(input), 0);
  const remaining = roundPaymentAmount(Math.max(0, pos.total() - paid));
  const line = document.createElement("div");
  line.className = "payment-line";
  line.dataset.paymentLineId = paymentLineId();
  if (previousLine) line.dataset.splitSource = previousLine.dataset.paymentLineId;
  line.innerHTML = `<select class="select" aria-label="${t("checkout.paymentMethod")}"><option value="CASH">${t("checkout.cash")}</option><option value="CC">${t("checkout.card")}</option></select><input class="input numeric" aria-label="${t("checkout.amount")}" type="number" inputmode="decimal" min="0.01" step="0.01" placeholder="${currency(0)}"><button class="btn" type="button" data-variant="ghost" data-size="icon" data-remove-payment aria-label="${t("checkout.removePayment")}">×</button>`;
  const input = line.querySelector("input");
  line.querySelector("select").value = method;
  input.value = String(remaining);
  input.dataset.previousAmount = String(remaining);
  paymentLines.append(line);
  updatePaymentChoice();
  updatePaymentCompletion();
  requestAnimationFrame(() => {
    input.focus({ preventScroll: true });
    input.select();
  });
}

function applySplitPayment(input) {
  const line = input.closest(".payment-line");
  const sourceId = line?.dataset.splitSource;
  const previousAmount = Number(input.dataset.previousAmount) || 0;
  const enteredAmount = paymentAmount(input);
  const source = sourceId && document.querySelector(`.payment-line[data-payment-line-id="${sourceId}"] input`);

  if (source) {
    const change = roundPaymentAmount(enteredAmount - previousAmount);
    const sourceAmount = paymentAmount(source);
    const totalBeforeChange = [...document.querySelectorAll("#payment-lines input")].reduce((sum, paymentInput) => sum + paymentAmount(paymentInput), 0) - enteredAmount + previousAmount;
    // Move as much of a larger entry as possible from its source row. Any
    // remainder is a deliberate overpayment and continues through change.
    // When reducing an overpayment, reduce the change before restoring an
    // allocation to the source row.
    const changeAbsorbed = change < 0 ? Math.min(-change, Math.max(0, totalBeforeChange - pos.total())) : 0;
    const transferred = change > 0 ? Math.min(change, sourceAmount) : change + changeAbsorbed;
    source.value = String(roundPaymentAmount(sourceAmount - transferred));
  }

  input.dataset.previousAmount = String(enteredAmount);
}

pos.subscribe(() => {
  const paymentStage = checkoutFlow.querySelector('[data-stage="payment"]');
  if (!checkoutFlow.hidden && !paymentStage.hidden) updatePaymentCompletion();
});

function updatePaymentChoice() {
  const credit = document.querySelector("#credit-toggle").getAttribute("aria-pressed") === "true";
  const methods = credit ? [t("checkout.credit")] : [...document.querySelectorAll(".payment-line select")].map((select) => select.value === "CC" ? t("checkout.card") : t("checkout.cash"));
  document.querySelector("#payment-choice").textContent = methods.length ? [...new Set(methods)].join(" + ") : "—";
}

startCheckoutButton.addEventListener("click", openCheckout);
document.querySelector("#checkout-cancel").addEventListener("click", closeCheckout);
checkoutFlow.addEventListener("click", (event) => {
  const next = event.target.closest("[data-checkout-next]");
  const back = event.target.closest("[data-checkout-back]");
  if (next) showCheckoutStage(next.dataset.checkoutNext);
  if (back) back.dataset.checkoutBack === "pos" ? closeCheckout() : showCheckoutStage(back.dataset.checkoutBack);
  const sequence = event.target.closest("[data-sequence]");
  if (sequence) { document.querySelectorAll("[data-sequence]").forEach((button) => { button.dataset.variant = button === sequence ? "default" : "secondary"; }); updateSequenceDescription(); }
});
document.querySelector("#customer-picker").addEventListener("click", () => { if (checkoutStage !== "payment") openCustomers("checkout"); });
document.querySelector("#customer-continue").addEventListener("click", () => showCheckoutStage("payment"));
document.querySelector("#delivery-toggle").addEventListener("click", (event) => { const active = event.currentTarget.getAttribute("aria-pressed") !== "true"; event.currentTarget.setAttribute("aria-pressed", String(active)); event.currentTarget.dataset.variant = active ? "default" : "outline"; const target = document.querySelector("#delivery-options"); target.hidden = !active; if (active) target.replaceChildren(...[100,150,200,250,300,400,500,600].map((amount) => { const button = document.createElement("button"); button.className = "btn"; button.dataset.variant = "secondary"; button.dataset.delivery = amount; button.textContent = currency(amount); return button; })); else { pos.setDelivery(0); document.querySelector("#delivery-summary").hidden = true; } updatePaymentCompletion(); });
document.querySelector("#delivery-options").addEventListener("click", (event) => { const button = event.target.closest("[data-delivery]"); if (!button) return; pos.setDelivery(Number(button.dataset.delivery)); document.querySelector("#delivery-summary").hidden = false; document.querySelectorAll("[data-delivery]").forEach((item) => item.dataset.variant = item === button ? "default" : "secondary"); updatePaymentCompletion(); });
document.querySelector("#add-payment-line").addEventListener("click", addPaymentLine);
document.querySelector("#payment-lines").addEventListener("click", (event) => { const button = event.target.closest("[data-remove-payment]"); if (!button) return; button.closest(".payment-line").remove(); document.querySelector("#payment-lines").dispatchEvent(new Event("input", { bubbles: true })); updatePaymentChoice(); });
document.querySelector("#payment-lines").addEventListener("change", () => { updatePaymentChoice(); updatePaymentCompletion(); });
document.querySelector("#payment-lines").addEventListener("input", (event) => { if (event.target.matches("input")) applySplitPayment(event.target); updatePaymentCompletion(); });
document.querySelector("#payment-lines").addEventListener("focusin", (event) => { if (mobileQuery.matches && event.target.matches("input")) event.target.scrollIntoView({ behavior: "smooth", block: "center" }); });
document.querySelector("#credit-toggle").addEventListener("click", (event) => { const active = event.currentTarget.getAttribute("aria-pressed") !== "true"; event.currentTarget.setAttribute("aria-pressed", String(active)); event.currentTarget.dataset.variant = active ? "default" : "outline"; document.querySelector("#payment-inputs").hidden = active; updatePaymentChoice(); updatePaymentCompletion(); });
function openReceiptPrint(invoice, copy = false) {
  const store = (companySettingsData.stores || []).find((entry) => Number(entry.id) === Number(invoice.store_id));
  completedReceipt = buildReceiptData(invoice, { company: companySettingsData.company, store, sequences: companySettingsData.sequence_sets, language: getLanguage(), t, copy });
  document.querySelector("#receipt-print-status").textContent = "";
  document.querySelector("#receipt-dialog-title").textContent = copy ? t("receipt.printCopy") : t("receipt.saleCompleted");
  document.querySelector("#receipt-print-description").textContent = t("receipt.printDescription");
  renderPrintTargets(); document.querySelector("#receipt-dialog").showModal();
}

function openPaymentReceiptPrint(invoice, payment) {
  const store = (companySettingsData.stores || []).find((entry) => Number(entry.id) === Number(invoice.store_id));
  completedReceipt = buildPaymentReceiptData(invoice, payment, { company: companySettingsData.company, store, sequences: companySettingsData.sequence_sets, language: getLanguage(), t });
  document.querySelector("#receipt-print-status").textContent = "";
  document.querySelector("#receipt-dialog-title").textContent = t("receipt.printPayment");
  document.querySelector("#receipt-print-description").textContent = t("receipt.paymentPrintDescription");
  renderPrintTargets(); document.querySelector("#receipt-dialog").showModal();
}

document.querySelector("#complete-sale").addEventListener("click", async () => { const complete = document.querySelector("#complete-sale"); const credit = document.querySelector("#credit-toggle").getAttribute("aria-pressed") === "true"; const payments = [...document.querySelectorAll(".payment-line")].map((line) => ({ type: line.querySelector("select").value, amount: Number(line.querySelector("input").value) || 0 })).filter((line) => line.amount); const draft = pos.receipt(); const additionalInfo = document.querySelector("#sale-additional-info").value.trim(); if (pos.isEmpty() || (!credit && payments.reduce((sum, line) => sum + line.amount, 0) < pos.total())) { updatePaymentCompletion(); return; } if (additionalInfo.length > 1000) { checkoutStatus.textContent = "Memo must be 1000 characters or fewer."; return; } complete.disabled = true; try { const savedSale = await createSale({ store_id: storeId, client_id: selectedCustomer.id, sequence_type: document.querySelector("[data-sequence][data-variant=default]").dataset.sequence, status: credit ? "CREDIT" : "CASH", sale_type: draft.delivery ? "FOR_DELIVER" : "IN_SHOP", delivery_charge: draft.delivery, discount: draft.order_discount, discount_type: draft.order_discount_type, discount_input: draft.order_discount_input, additional_info: additionalInfo, lines: draft.items.map((item) => ({ product_id: Number(item.id), quantity: item.qty, discount: item.discount, discount_type: item.discount_type, discount_input: item.discount_input })), payments: credit ? [] : payments }); invoicesStale = true; await refreshInventory(draft.items.map((item) => item.id)).catch(console.error); resetCompletedOrder(); closeCheckout(); openReceiptPrint(savedSale); } catch (error) { checkoutStatus.textContent = error.message; complete.disabled = false; } });
document.querySelector("#skip-print").addEventListener("click", () => { document.querySelector("#receipt-dialog").close(); completedReceipt = null; });
document.querySelector("#print-receipt").addEventListener("click", async () => {
  const button = document.querySelector("#print-receipt"), status = document.querySelector("#receipt-print-status");
  button.disabled = true; status.textContent = t("ui.printing");
  try {
    if (isDesktopTauri) { await printer.print(completedReceipt); status.textContent = t("ui.receiptPrinted"); setTimeout(() => document.querySelector("#receipt-dialog").close(), 500); completedReceipt = null; }
    else { const target = document.querySelector("#print-target").value; if (!target) throw new Error(t("ui.noDesktopPrinter")); await printRelay.requestPrint(uuid(), target, completedReceipt); clearTimeout(pendingPrintTimeout); pendingPrintTimeout = null; status.textContent = t("ui.receiptPrinted"); setTimeout(() => { document.querySelector("#receipt-dialog").close(); completedReceipt = null; }, 700); }
  } catch (error) { status.textContent = t("payment.printFailed", { error: errorMessage(error) }); }
  finally { button.disabled = false; }
});

pos.render();
renderCurrencyPlaceholders();
translateDocument();
onLanguageChange(() => {
  languageSwitcher.sync();
  updateStoreTitles();
  pos.render();
  renderCurrencyPlaceholders();
  renderProducts();
  updatePrinterStatus();
  if (!checkoutFlow.hidden) showCheckoutStage(checkoutStage);
  updateCustomerPicker();
  if (!customersScreen.hidden) loadCustomers();
});
updateCustomerPicker();
updatePrinterStatus();

// Authentication and user management share the existing tenant API and scope model.
const loginScreen = document.querySelector("#login-screen");
const loginForm = document.querySelector("#login-form");
const loginError = document.querySelector("#login-error");
const loginErrorMessage = document.querySelector("#login-error-message");
const loginStoreField = document.querySelector("#login-store-field");
const loginStoreSelect = document.querySelector("#login-store");
const googleLoginButton = document.querySelector("#google-login");
const usersNav = document.querySelector("#users-nav");
const userScreen = document.querySelector("#users-screen");
let managedUsers = [];
let assignmentOptions = { stores: [], scopes: [] };
let editingUser = null;
let userFilter = "";
let pendingLogin = null;

function allowed(permission) {
  const current = session()?.user;
  return current?.type === "admin" || current?.scopes === "admin" || current?.scopes?.includes(permission);
}
function showLogin(message = "") {
  userMenus.forEach((menu) => { menu.open = false; });
  appShell.hidden = true;
  loginScreen.hidden = false;
  loginError.hidden = !message;
  loginErrorMessage.textContent = message;
  requestAnimationFrame(() => document.querySelector("#login-identifier").focus());
}
function showLoginError(message) {
  loginErrorMessage.textContent = message;
  loginError.hidden = false;
}
function tauriPlatform() {
  return /Android|iPhone|iPad/i.test(navigator.userAgent) ? "mobile" : "desktop";
}
let activeGoogleLogin = null;
let googleLoginTimeout = null;
function joinGoogleLoginChannel(attempt, onResult) {
  let socket, stopped = false, joined = false, ref = 0, reconnectTimer;
  const topic = `login:${attempt.attempt_id}`;
  const send = (event, payload = {}) => socket?.readyState === WebSocket.OPEN && socket.send(JSON.stringify(["1", String(++ref), topic, event, payload]));
  const connect = () => {
    const url = new URL(API_BASE_URL);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    url.pathname = "/socket/websocket";
    url.search = new URLSearchParams({ vsn: "2.0.0", login_attempt_id: attempt.attempt_id, login_attempt_token: attempt.channel_token }).toString();
    socket = new WebSocket(url);
    socket.onopen = () => send("phx_join");
    socket.onmessage = ({ data }) => {
      const [, , messageTopic, event, payload] = JSON.parse(data);
      if (messageTopic !== topic) return;
      if (event === "phx_reply" && payload.status === "ok") { joined = true; onResult(payload.response); }
      if (event === "login_result") onResult(payload);
    };
    socket.onclose = () => { if (!stopped) reconnectTimer = setTimeout(connect, 1_500); };
  };
  connect();
  return { close: () => { stopped = true; clearTimeout(reconnectTimer); socket?.close(); }, ready: () => joined };
}
async function handleGoogleLoginResult(payload, attemptId) {
  if (!activeGoogleLogin || payload.attempt_id !== attemptId || payload.status === "pending") return;
  clearTimeout(googleLoginTimeout);
  if (payload.status === "error") {
    activeGoogleLogin.close(); activeGoogleLogin = null; googleLoginButton.disabled = false;
    showLoginError("Google sign-in was cancelled or could not be completed.");
    return;
  }
  activeGoogleLogin.close(); activeGoogleLogin = null;
  try { await requestStoreSelection(await exchangeTauriGoogleCode(payload.exchange_code)); }
  catch (error) { showLoginError(error.message || "Google sign-in could not be completed."); }
  finally { googleLoginButton.disabled = false; }
}
async function openGoogleLogin() {
  if (!window.__TAURI__) {
    showLoginError("Google sign-in is available in the desktop or mobile app.");
    return;
  }
  googleLoginButton.disabled = true;
  loginError.hidden = true;
  try {
    const attempt = await createTauriGoogleAttempt(tauriPlatform());
    activeGoogleLogin = joinGoogleLoginChannel(attempt, (payload) => handleGoogleLoginResult(payload, attempt.attempt_id));
    const startedAt = Date.now();
    while (!activeGoogleLogin.ready()) {
      if (Date.now() - startedAt > 10_000) throw new Error("Could not connect to sign-in service.");
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    const url = tauriGoogleAuthorizationUrl(tauriPlatform(), attempt.attempt_id);
    const invoke = window.__TAURI__?.core?.invoke;
    if (typeof invoke !== "function") throw new Error("The system browser is unavailable.");
    await invoke("open_external_url", { url });
    googleLoginTimeout = setTimeout(() => {
      activeGoogleLogin?.close(); activeGoogleLogin = null; googleLoginButton.disabled = false;
      showLoginError("Google sign-in timed out. Please try again.");
    }, 305_000);
  } catch (error) {
    showLoginError(error.message || "Could not open Google sign-in.");
    clearTimeout(googleLoginTimeout); activeGoogleLogin?.close(); activeGoogleLogin = null; googleLoginButton.disabled = false;
  }
}
async function requestStoreSelection(result) {
  pendingLogin = result;
  saveSession(result);
  try {
    const { entries } = await stores();
    if (!entries.length) throw new Error(t("ui.noStoreAccount"));
    loginStoreSelect.replaceChildren(new Option(t("ui.selectStore"), "", true, true), ...entries.map((store) => new Option(store.name, store.id)));
    loginStoreSelect.disabled = false;
    loginStoreField.hidden = false;
    loginForm.elements.identifier.disabled = true;
    loginForm.elements.password.disabled = true;
    googleLoginButton.disabled = true;
    document.querySelector("#login-submit").textContent = t("ui.loginContinue");
    requestAnimationFrame(() => loginStoreSelect.focus());
  } catch (error) {
    clearSession();
    pendingLogin = null;
    loginErrorMessage.textContent = error.message || t("ui.storesLoadError");
    loginError.hidden = false;
  }
}
function completeStoreSelection() {
  const selected = Number(loginStoreSelect.value);
  if (!Number.isInteger(selected) || selected <= 0 || !pendingLogin) { loginStoreSelect.focus(); loginStoreSelect.reportValidity(); return; }
  saveSession({ ...pendingLogin, store_id: selected });
  try { localStorage.setItem(POS_STORE_KEY, String(selected)); } catch {}
  pendingLogin = null;
  loginStoreField.hidden = true;
  loginStoreSelect.disabled = true;
  loginForm.elements.identifier.disabled = false;
  loginForm.elements.password.disabled = false;
  googleLoginButton.disabled = false;
  document.querySelector("#login-submit").textContent = "Sign in";
  loginForm.reset();
  showApplication();
}
function showApplication() {
  loginScreen.hidden = true;
  appShell.hidden = false;
  syncUserMenu();
  applyAuthorization();
  initializeStores().catch((error) => { console.error(error); productStatus.textContent = error.message || "Stores could not be loaded."; });
}
function currentUserIdentity() {
  const current = session()?.user || {};
  const login = current.login || current.username || current.email || "User";
  const name = current.name || [current.first_name, current.last_name].filter(Boolean).join(" ") || login;
  return { name, login, pic: current.pic, initials: name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join("").toUpperCase() || "U" };
}
function avatarSource(pic) {
  if (!pic || typeof pic !== "string") return "";
  if (pic.startsWith("data:image/")) return pic;
  const mime = pic.startsWith("iVBOR") ? "image/png" : pic.startsWith("R0lGOD") ? "image/gif" : pic.startsWith("UklGR") ? "image/webp" : "image/jpeg";
  return `data:${mime};base64,${pic.replace(/\s/g, "")}`;
}
function syncUserMenu() {
  const { name, login, pic, initials } = currentUserIdentity();
  document.querySelectorAll("[data-user-name]").forEach((element) => { element.textContent = name; });
  document.querySelectorAll("[data-user-login]").forEach((element) => { element.textContent = login; });
  document.querySelectorAll("[data-user-initials]").forEach((element) => { element.textContent = initials; });
  document.querySelectorAll("[data-avatar-image]").forEach((image) => {
    const source = avatarSource(pic);
    const fallback = image.nextElementSibling;
    image.hidden = !source;
    fallback.hidden = Boolean(source);
    image.src = source;
    image.onerror = () => { image.hidden = true; fallback.hidden = false; };
  });
  document.querySelectorAll(".avatar-trigger").forEach((element) => { element.setAttribute("aria-label", `Open menu for ${name}`); });
}
function logout() {
  printRelay?.close();
  clearInterval(printerAvailabilityTimer);
  clearSession();
  pendingLogin = null;
  loginStoreField.hidden = true;
  loginStoreSelect.disabled = true;
  loginForm.elements.identifier.disabled = false;
  loginForm.elements.password.disabled = false;
  googleLoginButton.disabled = false;
  document.querySelector("#login-submit").textContent = "Sign in";
  closeMobileNavigation({ restoreFocus: false });
  showLogin();
}
document.querySelectorAll("[data-logout]").forEach((button) => button.addEventListener("click", logout));
document.addEventListener("click", (event) => {
  userMenus.forEach((menu) => { if (menu.open && !menu.contains(event.target)) menu.open = false; });
});
function applyAuthorization() {
  const rules = { "pos-nav": "sales.pos", "sales-report-nav": "sales.view", "inventory-nav": "inventory.view", "orders-nav": "inventory.view", "company-settings-nav": "company.settings", "mobile-company-settings-nav": "company.settings", "users-nav": "user.view", "mobile-users-nav": "user.view", "create-product": "product.add", "create-order": "inventory.movement.request", "move-products": "inventory.movement.request" };
  Object.entries(rules).forEach(([id, permission]) => { const control = document.querySelector(`#${id}`); if (control) control.hidden = !allowed(permission); });
}
function activeUser(user) { return Number(user.is_active) === 1; }
function byActiveUserThenUsername(a, b) { return Number(activeUser(b)) - Number(activeUser(a)) || String(a.username || "").localeCompare(String(b.username || "")); }
function userName(user) { return [user.first_name, user.last_name].filter(Boolean).join(" ") || user.username; }
function storeNames(ids) { return (ids || []).map((id) => assignmentOptions.stores.find((store) => Number(store.id) === Number(id))?.name).filter(Boolean).join(", ") || t("user.noStores"); }
function userCheckboxes(items, selected, name, label) {
  const fieldset = document.createElement("fieldset"); fieldset.className = "form-fieldset user-assignment";
  const legend = document.createElement("legend"); legend.textContent = label; fieldset.appendChild(legend);
  const group = document.createElement("div"); group.className = "form-group";
  items.forEach((item) => { const row = document.createElement("div"); row.className = "form-field-inline"; const input = document.createElement("input"); input.type = "checkbox"; input.className = "checkbox"; input.name = name; input.value = item.id ?? item; input.id = `${name}-${input.value}`; input.checked = selected.includes(String(input.value)) || selected.includes(input.value); const inputLabel = document.createElement("label"); inputLabel.className = "label"; inputLabel.htmlFor = input.id; inputLabel.textContent = item.name || item; row.append(input, inputLabel); group.appendChild(row); }); fieldset.appendChild(group); return fieldset;
}
function renderUsers() {
  editingUser = null;
  userScreen.replaceChildren();
  const header = document.createElement("header"); header.className = "topbar users-header"; header.innerHTML = `<div class="brand-lockup"><span class="brand-mark" aria-hidden="true">E</span><div><p class="eyebrow">${t("user.users")}</p><h1 id="users-title" class="h3" tabindex="-1">${t("user.users")}</h1></div></div>`; addMobileNavigationTrigger(header);
  const actions = document.createElement("div"); actions.className = "users-header-actions";
  const filter = document.createElement("input"); filter.className = "input users-search"; filter.type = "search"; filter.placeholder = t("ui.searchUsers"); filter.setAttribute("aria-label", t("ui.searchUsers")); filter.value = userFilter; filter.addEventListener("input", () => { userFilter = filter.value.trim().toLowerCase(); renderUsers(); }); actions.appendChild(filter);
  if (allowed("user.setting")) { const add = document.createElement("button"); add.className = "btn"; add.type = "button"; add.dataset.variant = "default"; add.textContent = t("user.create"); add.addEventListener("click", () => renderUserForm()); actions.appendChild(add); }
  header.appendChild(actions); userScreen.appendChild(header);
  const status = document.createElement("p"); status.className = "users-status"; status.setAttribute("role", "status"); userScreen.appendChild(status);
  const list = document.createElement("div"); list.className = "user-list";
  managedUsers.filter((user) => `${userName(user)} ${user.username || ""} ${(user.scopes || []).join(" ")}`.toLowerCase().includes(userFilter)).sort(byActiveUserThenUsername).forEach((user) => { const card = document.createElement("article"); card.className = `card user-card ${activeUser(user) ? "" : "is-inactive"}`.trim(); const body = document.createElement("div"); body.className = "card-content"; const heading = document.createElement("div"); heading.className = "user-card-heading"; const title = document.createElement("h3"); title.className = "card-title"; title.textContent = userName(user); const badge = document.createElement("span"); badge.className = `user-status ${activeUser(user) ? "is-active" : ""}`; badge.textContent = activeUser(user) ? t("user.active") : t("user.inactive"); heading.append(title, badge); const meta = document.createElement("dl"); meta.className = "user-meta"; [[t("user.username"), user.username], [t("user.userType"), t("user.employee")], [t("user.stores"), storeNames(user.store_ids)], [t("user.permissions"), user.scopes?.join(", ") || t("user.noPermissions")]].forEach(([term, value]) => { const row = document.createElement("div"); const dt = document.createElement("dt"); dt.textContent = term; const dd = document.createElement("dd"); dd.textContent = value; row.append(dt, dd); meta.appendChild(row); }); body.append(heading, meta); const footer = document.createElement("div"); footer.className = "card-footer"; const view = document.createElement("button"); view.className = "btn"; view.type = "button"; view.dataset.variant = "outline"; view.textContent = t("user.view"); view.addEventListener("click", () => renderUserForm(user, true)); footer.appendChild(view); if (allowed("user.setting")) { const edit = document.createElement("button"); edit.className = "btn"; edit.type = "button"; edit.dataset.variant = "default"; edit.textContent = t("user.edit"); edit.addEventListener("click", () => renderUserForm(user)); footer.appendChild(edit); if (activeUser(user)) { const deactivate = document.createElement("button"); deactivate.className = "btn"; deactivate.type = "button"; deactivate.dataset.variant = "destructive"; deactivate.textContent = t("user.deactivate"); deactivate.addEventListener("click", async () => { if (!confirm(t("ui.deactivateQuestion", { name: userName(user) }))) return; try { await deactivateUser(user.id); await loadUsers(); } catch (error) { status.textContent = error.message; } }); footer.appendChild(deactivate); } } card.append(body, footer); list.appendChild(card); });
  if (!managedUsers.length) status.textContent = t("user.noUsers"); userScreen.appendChild(list); translateDocument(userScreen);
}
function renderUserForm(user = null, readOnly = false) {
  editingUser = user; userScreen.replaceChildren();
  const heading = document.createElement("header"); heading.className = "users-header"; heading.innerHTML = `<div><p class="eyebrow">${t("user.users")}</p><h2 id="users-title" class="h3" tabindex="-1">${readOnly ? t("user.details") : user ? t("user.edit") : t("user.create")}</h2></div>`; addMobileNavigationTrigger(heading); userScreen.appendChild(heading);
  const card = document.createElement("div"); card.className = "card user-form-card"; const content = document.createElement("div"); content.className = "card-content"; const form = document.createElement("form"); form.className = "form"; form.noValidate = true;
  [["first_name", "First name", "text", true], ["last_name", "Last name", "text", true], ["username", "Username", "text", true], ["password", user ? "New password (leave blank to keep current)" : "Password", "password", !user]].forEach(([name, label, type, required]) => { const field = document.createElement("div"); field.className = "form-field"; const input = document.createElement("input"); input.className = "input"; input.name = name; input.id = `user-${name}`; input.type = type; input.required = required; input.value = type === "password" ? "" : user?.[name] || ""; input.disabled = readOnly; const inputLabel = document.createElement("label"); inputLabel.className = "label"; inputLabel.htmlFor = input.id; inputLabel.textContent = label; field.append(inputLabel, input); form.appendChild(field); });
  const active = document.createElement("div"); active.className = "form-field-inline"; active.innerHTML = '<input id="user-active" class="checkbox" type="checkbox" name="is_active"><label class="label" for="user-active">Active user</label>'; active.querySelector("input").checked = user ? Number(user.is_active) === 1 : true; active.querySelector("input").disabled = readOnly; form.appendChild(active);
  form.append(userCheckboxes(assignmentOptions.stores, user?.store_ids || [], "store_ids", "Assigned stores"), userCheckboxes(assignmentOptions.scopes, user?.scopes || [], "scopes", "Permissions")); form.querySelectorAll("input").forEach((input) => { if (readOnly) input.disabled = true; });
  const message = document.createElement("p"); message.className = "field-description"; message.role = "status"; form.appendChild(message); const footer = document.createElement("div"); footer.className = "form-actions"; const cancel = document.createElement("button"); cancel.className = "btn"; cancel.type = "button"; cancel.dataset.variant = "outline"; cancel.textContent = readOnly ? t("action.back") : t("action.cancel"); cancel.addEventListener("click", renderUsers); footer.appendChild(cancel); if (!readOnly) { const save = document.createElement("button"); save.className = "btn"; save.type = "submit"; save.dataset.variant = "default"; save.textContent = t("user.save"); footer.appendChild(save); } form.appendChild(footer); form.addEventListener("submit", async (event) => { event.preventDefault(); if (!form.reportValidity()) return; const attrs = Object.fromEntries(new FormData(form)); attrs.is_active = form.elements.is_active.checked ? 1 : 0; attrs.store_ids = [...form.querySelectorAll('[name="store_ids"]:checked')].map((input) => Number(input.value)); attrs.scopes = [...form.querySelectorAll('[name="scopes"]:checked')].map((input) => input.value); if (!attrs.password) delete attrs.password; try { const save = form.querySelector('[type="submit"]'); save.disabled = true; user ? await updateUser(user.id, attrs) : await createUser(attrs); await loadUsers(); } catch (error) { message.textContent = error.message; } }); content.appendChild(form); card.appendChild(content); userScreen.appendChild(card); translateDocument(userScreen); requestAnimationFrame(() => document.querySelector("#users-title").focus());
}
async function loadUsers() { try { [managedUsers, assignmentOptions] = await Promise.all([users(), userOptions()]); renderUsers(); } catch (error) { if (error.status === 403) showUnauthorized(); else { renderUsers(); userScreen.querySelector(".users-status").textContent = error.message; } } }
function closeUsersPage() {
  appShell.classList.remove("users-view");
  userScreen.hidden = true;
  if (location.hash === "#/users") history.replaceState(null, "", `${location.pathname}${location.search}#/pos`);
}
function showUnauthorized() { userScreen.hidden = false; appShell.classList.add("users-view"); userScreen.innerHTML = `<div class="card unauthorized-card"><div class="card-header"><p class="eyebrow">${t("unauthorized.accessDenied")}</p><h1 id="users-title" class="card-title">${t("unauthorized.message")}</h1><p class="card-description">${t("unauthorized.description")}</p></div></div>`; }
function renderUsersRoute() {
  if (!allowed("user.view")) return showUnauthorized();
  appShell.classList.remove("invoice-view");
  appShell.classList.add("users-view");
  userScreen.hidden = false;
  selectSidebar("users-nav");
  loadUsers();
}
function openUsers() {
  if (location.hash !== "#/users") { location.hash = "/users"; return; }
  renderUsersRoute();
}
function handleRoute() {
  if (location.hash === "#/users") renderUsersRoute();
  else openPos();
}
usersNav.addEventListener("click", openUsers);
window.addEventListener("hashchange", handleRoute);
document.addEventListener("click", (event) => {
  const protectedControl = event.target.closest("#sales-report-nav, #inventory-nav, #orders-nav, #company-settings-nav, #create-product, #create-order, #move-products");
  if (!protectedControl) return;
  const permission = { "sales-report-nav": "sales.view", "inventory-nav": "inventory.view", "orders-nav": "inventory.view", "company-settings-nav": "company.settings", "create-product": "product.add", "create-order": "inventory.movement.request", "move-products": "inventory.movement.request" }[protectedControl.id];
  if (!allowed(permission)) { event.preventDefault(); event.stopImmediatePropagation(); showUnauthorized(); }
}, true);
loginForm.addEventListener("submit", async (event) => { event.preventDefault(); loginError.hidden = true; if (pendingLogin) { completeStoreSelection(); return; } if (!loginForm.reportValidity()) return; const submit = document.querySelector("#login-submit"); submit.disabled = true; try { await requestStoreSelection(await login(loginForm.elements.identifier.value.trim(), loginForm.elements.password.value)); } catch (error) { loginErrorMessage.textContent = error.code === "SERVER_UNAVAILABLE" ? t("auth.serverUnavailable") : error.status === 401 ? t("auth.invalidCredentials") : t("auth.unableToSignIn"); loginError.hidden = false; } finally { submit.disabled = false; } });
googleLoginButton.addEventListener("click", openGoogleLogin);
onLanguageChange(() => { if (!userScreen.hidden) editingUser ? renderUserForm(editingUser) : renderUsers(); });

createMobilePullToRefresh({
  screen: catalogPanel.querySelector(".catalog-content"),
  onRefresh: () => loadProducts({ reset: true }),
  isActive: () => !catalogPanel.dataset.view,
  scrollContainer: document.scrollingElement
});
createMobilePullToRefresh({
  screen: customersScreen,
  onRefresh: () => loadCustomers()
});
createMobilePullToRefresh({
  screen: invoiceReport,
  onRefresh: () => loadInvoices({ reset: true, preserveExpanded: true, quiet: true })
});
createMobilePullToRefresh({
  screen: inventoryScreen,
  onRefresh: () => loadInventory(null, { preserveContext: true })
});
createMobilePullToRefresh({
  screen: ordersScreen,
  onRefresh: () => loadOrders()
});

if (session()?.token && session()?.store_id) { showApplication(); handleRoute(); } else if (session()?.token) { showLogin(); requestStoreSelection(session()); } else showLogin();
