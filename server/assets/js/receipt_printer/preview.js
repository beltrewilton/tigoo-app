import {ReceiptFormatter} from "./formatter"

// Render the same document consumed by ReceiptEncoder, preserving its column spacing.
export function showReceiptPreview(payload, config) {
  document.getElementById("ui-receipt-preview")?.remove()
  const formatter = new ReceiptFormatter(config)
  const sale = payload.invoice || payload.receipt || payload.sale
  const lines = payload.payment ? formatter.payment(sale, payload.payment)
    : payload.invoice ? formatter.invoice(sale) : formatter.receipt(sale)
  const dialog = document.createElement("dialog")
  dialog.id = "ui-receipt-preview"
  dialog.setAttribute("aria-label", "Ver Recibo")
  dialog.style.cssText = "padding:16px;border:0;border-radius:8px;max-width:calc(100vw - 24px);max-height:90vh;color:#111;background:#eee;box-shadow:0 12px 48px #0006;"
  const close = document.createElement("button")
  close.type = "button"
  close.className = "btn"
  close.textContent = "Cerrar"
  close.style.cssText = "display:block;margin:0 0 12px auto;"
  close.addEventListener("click", () => dialog.close())
  const paper = document.createElement("article")
  paper.setAttribute("aria-label", "Recibo")
  paper.style.cssText = `box-sizing:content-box;width:${formatter.config.columns}ch;padding:20px;background:white;font-family:monospace;font-size:12px;line-height:1.3;`
  for (const line of lines) {
    const row = document.createElement("div")
    row.style.textAlign = line.align || "left"
    if (line.type === "image") {
      const image = document.createElement("img")
      image.src = line.image
      image.alt = "Logo"
      image.style.cssText = `width:${line.width}px;max-width:100%;height:auto;filter:grayscale(1);`
      row.append(image)
    } else {
      row.textContent = line.text || "\u00a0"
      row.style.whiteSpace = "pre-wrap"
      row.style.overflowWrap = "anywhere"
      row.style.fontWeight = line.bold ? "bold" : "normal"
      row.style.fontStyle = line.italic ? "italic" : "normal"
    }
    paper.append(row)
  }
  dialog.append(close, paper)
  dialog.addEventListener("close", () => dialog.remove(), {once: true})
  document.body.append(dialog)
  dialog.showModal()
  close.focus()
}
