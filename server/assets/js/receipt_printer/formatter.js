import {LANGUAGES, getLanguage, money, t} from "../i18n"

const str = value => value == null ? "" : String(value)

export class ReceiptFormatter {
  constructor(config = {}) {
    this.config = {columns: 48, ...config}
  }

  receipt(sale) {
    console.log("[printer] ReceiptFormatter.receipt", {sequence: sale?.sequence, copyLabel: ""})
    return this.document("", sale)
  }

  payment(sale, payment) {
    console.log("[printer] ReceiptFormatter.payment", {sequence: sale?.sequence, paymentId: payment?.id, copyLabel: ""})
    return this.document("", sale, payment)
  }

  invoice(sale) {
    console.log("[printer] ReceiptFormatter.invoice", {sequence: sale?.sequence, copyLabel: t("receipts.copy")})
    return this.document(t("receipts.copy"), sale)
  }

  reconciliation(report) {
    const columns = this.config.columns
    const store = report.store || {}
    const lines = [
      {align: "center", text: str(report.company_name || store.name || "TIGOO").toUpperCase()},
      store.address ? {align: "center", text: wrap(str(store.address).toUpperCase(), columns)} : null,
      {text: rule(columns)},
      {align: "center", text: "CASH RECONCILIATION"},
      {text: rule(columns)},
      {text: twoCol("Cashier", str(report.cashier || ""), columns)},
      {text: twoCol("Printed at", str(report.generated_at || report.date || ""), columns)},
      {text: reconciliationAmountLine("Opening cash", report.opening_cash, columns)},
      {text: rule(columns)},
      {text: "SALES"},
      {text: rule(columns)}
    ].filter(Boolean)

    for (const sale of report.sales || []) {
      lines.push({text: reconciliationAmountLine(str(sale.customer_name || ""), sale.amount, columns)})
      if (sale.date) lines.push({text: str(sale.date).slice(0, columns)})
    }

    lines.push(
      {text: rule(columns)},
      {text: twoCol("Sales count", str(report.sales_count || 0), columns)},
      {text: reconciliationAmountLine("Total sales", report.total_sales, columns)},
      {text: rule(columns)}
    )

    for (const item of report.payment_totals || []) lines.push({text: reconciliationAmountLine(item.label || paymentLabel(item.type), item.amount, columns)})
    lines.push({text: rule(columns)})
    lines.push({bold: true, text: reconciliationAmountLine("Expected drawer", report.expected_cash, columns)})
    lines.push({text: rule(columns)})
    lines.push({align: "center", text: "END OF REPORT"})
    return lines
  }

  document(copyLabel, sale, payment = null) {
    const columns = this.config.columns
    const store = sale.store || {}
    const client = sale.client || sale.customer || {}
    const payments = receiptPayments(sale, payment)
    const paid = sum(payments.map(item => item.amount))
    const paidToDate = number(sale.total_paid) > 0 ? number(sale.total_paid) : paid
    const pending = Math.max(0, number(sale.due_balance ?? number(sale.amount) - paid))
    const totals = receiptTotals(sale)
    const items = sum((sale.lines || []).map(line => line.quantity || line.qty || 0))
    const sequence = str(sale.sequence || sale.id || "-")

    const lines = [
      sale.ecf_test === true ? {align: "center", bold: true, text: "eCF Test"} : null,
      sale.ecf_test === true ? {align: "center", text: "TEST RECEIPT - NO COMMERCIAL SALE"} : null,
      store.logo ? {type: "image", image: store.logo, align: "center", width: 286} : null,
      store.address ? {align: "center", text: wrap(str(store.address).toUpperCase(), columns)} : null,
      store.slogan ? {align: "center", text: wrap(str(store.slogan).toUpperCase(), columns)} : null,
      {text: rule(columns)},
      {text: twoCol(t("receipts.rnc"), str(store.company_id || store.rnc || store.company_rnc || ""), columns)},
      {text: twoCol(t("receipts.encf"), sequence, columns)},
      {text: twoCol(t("receipts.date"), receiptDate(sale.date_create), columns)},
      {text: twoCol(t("receipts.store"), str(store.name || ""), columns)},
      {text: twoCol(t("receipts.customer"), str(sale.client_name || client.name || t("receipts.consumerFinal")), columns)},
      {text: twoCol(t("receipts.document"), str(sale.client_document_id || client.document_id || ""), columns)},
      {text: twoCol(t("receipts.celphone"), str(sale.client_celphone || client.celphone || client.phone || ""), columns)},
      {text: twoCol(t("receipts.salesperson"), str(sale.login || ""), columns)},
      copyLabel ? {align: "center", text: copyLabel} : null,
      {align: "center", text: sale.status === "CREDIT" ? t("receipts.creditInvoice") : t("receipts.salesJournal")},
      {text: rule(columns)},
      {text: columnsHeader(columns)},
      {text: rule(columns)}
    ].filter(Boolean)

    for (const item of sale.lines || sale.items || []) {
      const product = item.product || {}
      const name = str(item.name || product.name || `${t("receipts.product")} ${item.product_id || ""}`).toUpperCase()
      const sku = str(product.code || item.code || item.sku || item.product_id || "")
      const qty = number(item.quantity || item.qty || 1)
      const unit = number(item.amount || item.price || product.price || 0)
      const total = lineQuotedTotal(item)
      const tax = itemTax(item, total, sale.ecf_test === true)
      lines.push({text: wrap(name, columns)})
      if (sku) lines.push({text: `SKU: ${sku}`.slice(0, columns)})
      lines.push({text: itemLine(qty, unit, tax, total, columns)})
    }

    lines.push({text: rule(columns)})
    lines.push({italic: true, text: amountLine(t("receipts.quoted"), totals.quoted, columns)})
    if (totals.discount > 0) lines.push({bold: true, text: amountLine(t("receipts.purchaseSavings"), -totals.discount, columns)})
    lines.push({text: ""})
    lines.push({text: amountLine(t("common.subtotal"), totals.subtotal, columns)})
    lines.push({text: amountLine(t("receipts.itbis"), totals.tax, columns)})
    if (totals.delivery > 0) lines.push({text: amountLine(t("receipts.delivery"), totals.delivery, columns)})
    lines.push({bold: true, text: amountLine(t("common.total"), totals.total, columns)})
    lines.push({text: rule(columns)})

    for (const item of payments) lines.push({text: paymentLine(item, columns)})
    if (payment && paidToDate > 0) lines.push({text: amountLine(t("receipts.paidToDate"), paidToDate, columns)})
    if (payment && pending > 0) lines.push({text: amountLine(t("receipts.pendingBalance"), pending, columns)})
    if (number(sale.change_amount) > 0) lines.push({text: amountLine(t("receipts.change"), sale.change_amount, columns)})
    lines.push({text: twoCol(t("receipts.articles"), trimNumber(items), columns)})

    if (str(sale.additional_info).trim()) {
      lines.push({text: rule(columns)})
      lines.push({bold: true, text: str(t("receipts.additionalInfo")).toUpperCase().slice(0, columns)})
      lines.push({text: wrap(str(sale.additional_info).trim().toUpperCase(), columns)})
    }

    lines.push({text: rule(columns)})
    lines.push({align: "center", text: t("receipts.thanks")})
    lines.push({align: "center", text: `${t("receipts.receipt")}: ${sequence}`})
    return lines
  }
}

function columnsHeader(columns) {
  return twoCol(t("receipts.description"), `${t("receipts.itbis")}      ${t("receipts.value")}`, columns)
}

function itemLine(qty, unit, tax, total, columns) {
  const left = `${trimNumber(qty)} x ${receiptMoney(unit)}`
  const taxValue = receiptMoney(tax)
  const right = receiptMoney(total)
  const taxColumn = taxValue.padStart(10)
  const rightColumn = right.padStart(12)
  return `${left}`.padEnd(Math.max(1, columns - taxColumn.length - rightColumn.length)).slice(0, columns - taxColumn.length - rightColumn.length) + taxColumn + rightColumn
}

function itemTax(item, total, ecfTest = false) {
  if (ecfTest && item.ecf_tax_indicator != null) {
    const factor = {"1": 1.18, "2": 1.16, "3": 1, "4": 1}[item.ecf_tax_indicator] || 1
    return Math.max(0, total - total / factor)
  }
  const explicit = number(item.tax_amount || item.tax)
  if (explicit > 0) return explicit
  const subtotal = number(item.sub || item.subtotal || 0)
  if (subtotal > 0) return Math.max(0, total - subtotal)
  return Math.max(0, total - total / 1.18)
}

function lineQuotedTotal(item) {
  const qty = number(item.quantity || item.qty || 1)
  const unit = number(item.amount || item.price || item.product?.price || 0)
  return unit * qty
}

function receiptTotals(sale) {
  const total = number(sale.amount || sale.total)
  // Test receipts include delivery as its own fiscal item and in tax totals.
  const delivery = sale.ecf_test === true ? 0 : number(sale.delivery_charge || sale.delivery)
  const subtotal = number(sale.sub || sale.subtotal)
  const tax = number(sale.tax_amount || sale.tax)
  const discount = number(sale.discount || 0)
  const quoted = total - delivery + discount
  return {quoted, discount, subtotal, tax, delivery, total}
}

function amountLine(label, value, columns) {
  return twoCol(label, receiptMoney(value), columns)
}

function receiptMoney(value) {
  if (getLanguage() !== "pt") return money(value)
  const amount = number(value)
  const formatted = Math.abs(amount).toLocaleString("en-US", {minimumFractionDigits: 2, maximumFractionDigits: 2})
  return `${amount < 0 ? "-" : ""}$${formatted}`
}

function reconciliationAmountLine(label, value, columns) {
  return twoCol(label, plainMoney(value), columns)
}

function plainMoney(value) {
  return `$ ${number(value).toFixed(2)}`
}

function twoCol(left, right, columns) {
  left = str(left)
  right = str(right)
  const space = Math.max(1, columns - left.length - right.length)
  return `${left}${" ".repeat(space)}${right}`
}

function rule(columns) {
  return "-".repeat(columns)
}

function wrap(value, columns) {
  const words = str(value).split(/\s+/)
  const result = []
  let line = ""
  for (const word of words) {
    if (`${line} ${word}`.trim().length > columns) {
      if (line) result.push(line)
      line = word
    } else {
      line = `${line} ${word}`.trim()
    }
  }
  if (line) result.push(line)
  return result.join("\n")
}

function receiptDate(value) {
  const date = value ? new Date(value) : new Date()
  if (Number.isNaN(date.getTime())) return str(value)
  return date.toLocaleString(currentLocale(), {year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit"})
}

function paymentLabel(type) {
  const labels = {
    en: {CC: "Credit Card", CASH: "Cash"},
    es: {CC: "Tarjeta de credito", CASH: "Efectivo"},
    pt: {CC: "Cartao de credito", CASH: "Dinheiro"}
  }
  const language = getLanguage()
  return labels[language]?.[type] || labels.en[type] || str(type)
}

function paymentLine(payment, columns) {
  const amount = receiptMoney(payment.amount)
  return twoCol(paymentLabel(payment.type), amount, columns)
}

function receiptPayments(sale, payment) {
  const payments = [...(sale.payments || sale.sale_paids || [])]
  if (!payment) return payments
  const exists = payments.some(item => item.id != null && payment.id != null && String(item.id) === String(payment.id))
  return exists ? payments : [...payments, payment]
}

function shortDate(value) {
  const date = value ? new Date(value) : null
  if (!date || Number.isNaN(date.getTime())) return str(value)
  return date.toLocaleDateString(currentLocale(), {year: "numeric", month: "2-digit", day: "2-digit"})
}

function columnAmountLine(label, value, columns) {
  const amount = money(value)
  const amountColumn = amount.padStart(12)
  return str(label).padEnd(columns - amountColumn.length).slice(0, columns - amountColumn.length) + amountColumn
}

function number(value) {
  return Number(value || 0)
}

function sum(values) {
  return values.reduce((total, value) => total + number(value), 0)
}

function trimNumber(value) {
  return Number.isInteger(Number(value)) ? String(Number(value)) : Number(value).toFixed(2)
}

function currentLocale() {
  return LANGUAGES[getLanguage()]?.locale || LANGUAGES.en.locale
}
