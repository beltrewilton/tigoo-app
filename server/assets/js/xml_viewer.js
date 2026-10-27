// Presentation only. Download and copy always use the original signed XML.
export const XmlViewer = {
  mounted() {
    this.original = new TextDecoder().decode(Uint8Array.from(atob(this.el.dataset.xmlSource), char => char.charCodeAt(0)))
    this.code = this.el.querySelector("[data-xml-code]")
    this.status = this.el.querySelector("[data-xml-status]")
    this.formatted = prettyXml(this.original)
    this.onClick = async event => {
      const button = event.target.closest("button")
      if (!button) return
      if (button.hasAttribute("data-xml-wrap")) {
        const wrapped = this.code.classList.toggle("is-wrapped")
        button.setAttribute("aria-pressed", String(wrapped))
      } else if (button.hasAttribute("data-copy-xml") || button.hasAttribute("data-copy-hash")) {
        try {
          await navigator.clipboard.writeText(button.hasAttribute("data-copy-hash") ? this.el.dataset.xmlHash : this.original)
          this.status.textContent = button.hasAttribute("data-copy-hash") ? "Checksum copied" : "Original XML copied"
        } catch {
          this.status.textContent = "Copy is unavailable. Download the original XML instead."
        }
      }
    }
    this.renderXml = () => {
      const text = this.formatted
      this.code.replaceChildren()
      const fragment = document.createDocumentFragment()
      for (const [index, line] of text.split("\n").entries()) {
        const row = document.createElement("span")
        row.className = "ecf-xml-line"
        row.dataset.line = String(index + 1)
        const content = document.createElement("span")
        content.className = "ecf-xml-line-content"
        highlightLine(content, line)
        row.append(content)
        fragment.append(row)
      }
      this.code.append(fragment)
      this.el.querySelector("[data-xml-lines]").textContent = `${text.split("\n").length.toLocaleString()} lines`
    }
    this.el.addEventListener("click", this.onClick)
    this.renderXml()
  },
  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  }
}

function prettyXml(source) {
  const document = new DOMParser().parseFromString(source, "application/xml")
  if (document.querySelector("parsererror")) return source
  const serializer = new XMLSerializer()
  const indent = level => "  ".repeat(level)
  const format = (node, level) => {
    if (node.nodeType !== 1) return indent(level) + serializer.serializeToString(node)
    const children = Array.from(node.childNodes)
    const hasElements = children.some(child => child.nodeType === 1)
    const mixedContent = children.some(child => child.nodeType === 4 || (child.nodeType === 3 && child.nodeValue.trim() !== ""))
    if (!hasElements || mixedContent) return indent(level) + serializer.serializeToString(node)
    const opening = serializer.serializeToString(node.cloneNode(false)).replace(/\s*\/>$/, ">")
    const content = children.filter(child => child.nodeType !== 3 || child.nodeValue.trim() !== "")
    return [indent(level) + opening, ...content.map(child => format(child, level + 1)), `${indent(level)}</${node.nodeName}>`].join("\n")
  }
  const declaration = source.match(/^\uFEFF?\s*(<\?xml[\s\S]*?\?>)/)?.[1]
  return [declaration, ...Array.from(document.childNodes).filter(node => node.nodeType !== 3).map(node => format(node, 0))].filter(Boolean).join("\n")
}

function highlightLine(parent, source) {
  const tokens = /(<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<\/?[A-Za-z_][\w:.-]*(?:[^"'<>]|"[^"]*"|'[^']*')*?>)/g
  let offset = 0
  for (const match of source.matchAll(tokens)) {
    parent.append(document.createTextNode(source.slice(offset, match.index)))
    const token = document.createElement("span")
    token.className = match[0].startsWith("<!--") ? "ecf-xml-comment" : "ecf-xml-tag"
    // XML is always inserted as text, never interpreted as HTML.
    token.textContent = match[0]
    parent.append(token)
    offset = match.index + match[0].length
  }
  parent.append(document.createTextNode(source.slice(offset)))
}

export const EcfRowInspector = {
  mounted() {
    this.returnFocus = document.activeElement
    this.position = () => {
      const row = document.getElementById(this.el.dataset.anchor)
      const panel = this.el.closest(".catalog-panel")
      const gutter = window.innerWidth < 640 ? 8 : 16
      const width = Math.min(1440, window.innerWidth - gutter * 2, panel?.clientWidth || window.innerWidth)
      const rowBounds = row?.getBoundingClientRect()
      const panelBounds = panel?.getBoundingClientRect()
      const desiredTop = rowBounds ? rowBounds.bottom + 8 : 80
      const top = Math.max(gutter, Math.min(desiredTop, window.innerHeight - 240))
      const left = Math.max(gutter, Math.min(panelBounds?.left || gutter, window.innerWidth - width - gutter))
      Object.assign(this.el.style, {width: `${width}px`, left: `${left}px`, top: `${top}px`,
        maxHeight: `${window.innerHeight - top - gutter}px`})
    }
    const row = document.getElementById(this.el.dataset.anchor)
    if (row && window.innerHeight - row.getBoundingClientRect().bottom < 280) {
      row.scrollIntoView({block: "start", inline: "nearest"})
    }
    if (this.el.open) this.el.close()
    this.el.showModal()
    this.position()
    this.onCancel = event => {
      event.preventDefault()
      this.pushEvent("close_xml_inspector", {})
    }
    this.onResize = () => {
      cancelAnimationFrame(this.positionFrame)
      this.positionFrame = requestAnimationFrame(this.position)
    }
    this.el.addEventListener("cancel", this.onCancel)
    window.addEventListener("resize", this.onResize)
    window.addEventListener("scroll", this.onResize, true)
  },
  updated() {
    if (!this.el.open) this.el.showModal()
    this.position()
  },
  destroyed() {
    cancelAnimationFrame(this.positionFrame)
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("scroll", this.onResize, true)
    this.el.removeEventListener("cancel", this.onCancel)
    if (this.returnFocus?.isConnected) this.returnFocus.focus({preventScroll: true})
  }
}
