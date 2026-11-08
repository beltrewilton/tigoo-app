import {receiptText} from "./text.js"

const DEFAULT_CONFIG = {
  printerModel: null,
  language: "esc-pos",
  columns: 48,
  imageMode: "column",
  feedBeforeCut: 4,
  newline: "\n"
}

export class ReceiptEncoder {
  constructor(config = {}) {
    this.config = {...DEFAULT_CONFIG, ...config}
    this.bytes = []
  }

  initialize() {
    this.bytes.push(0x1b, 0x40)
    return this
  }

  align(value = "left") {
    const modes = {left: 0, center: 1, right: 2}
    this.bytes.push(0x1b, 0x61, modes[value] ?? 0)
    return this
  }

  bold(enabled = true) {
    this.bytes.push(0x1b, 0x45, enabled ? 1 : 0)
    return this
  }

  italic(enabled = true) {
    this.bytes.push(0x1b, 0x34, enabled ? 1 : 0)
    return this
  }

  size(width = 1, height = 1) {
    const widthBits = Math.max(0, Math.min(7, Number(width) - 1 || 0))
    const heightBits = Math.max(0, Math.min(7, Number(height) - 1 || 0))
    this.bytes.push(0x1d, 0x21, (widthBits << 4) | heightBits)
    return this
  }

  text(value = "") {
    this.bytes.push(...new TextEncoder().encode(receiptText(value)))
    return this
  }

  line(value = "") {
    this.text(value)
    return this.newline()
  }

  newline() {
    this.bytes.push(...new TextEncoder().encode(this.config.newline))
    return this
  }

  feed(lines = 1) {
    this.bytes.push(0x1b, 0x64, Math.max(0, Math.min(255, Number(lines) || 0)))
    return this
  }

  cut() {
    if (this.config.feedBeforeCut > 0) this.feed(this.config.feedBeforeCut)
    this.bytes.push(0x1d, 0x56, 0x00)
    return this
  }

  qrcode(value, options = {}) {
    const data = new TextEncoder().encode(String(value))
    const size = Math.max(1, Math.min(8, Number(options.size) || 6))
    const length = data.length + 3
    this.bytes.push(0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x43, size)
    this.bytes.push(0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x45, 48)
    this.bytes.push(0x1d, 0x28, 0x6b, length & 0xff, length >> 8, 0x31, 0x50, 0x30, ...data)
    this.bytes.push(0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x51, 0x30)
    return this
  }

  async image(source, options = {}) {
    const {bytes, width, height} = await rasterizeImage(source, options.width || 220)
    const widthBytes = Math.ceil(width / 8)
    this.bytes.push(0x1d, 0x76, 0x30, 0x00, widthBytes & 0xff, widthBytes >> 8, height & 0xff, height >> 8)
    this.bytes.push(...bytes)
    this.newline()
    return this
  }

  encode() {
    return new Uint8Array(this.bytes)
  }
}

async function rasterizeImage(source, targetWidth) {
  const image = new Image()
  image.src = source
  await image.decode()
  const width = Math.max(8, Math.min(512, Math.round(targetWidth / 8) * 8))
  const height = Math.max(1, Math.round(image.height * (width / image.width)))
  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height
  const context = canvas.getContext("2d", {willReadFrequently: true})
  context.fillStyle = "#fff"
  context.fillRect(0, 0, width, height)
  context.drawImage(image, 0, 0, width, height)
  const pixels = context.getImageData(0, 0, width, height).data
  const bytes = []
  for (let y = 0; y < height; y++) {
    for (let xByte = 0; xByte < width / 8; xByte++) {
      let byte = 0
      for (let bit = 0; bit < 8; bit++) {
        const x = xByte * 8 + bit
        const offset = (y * width + x) * 4
        const luminance = pixels[offset] * 0.299 + pixels[offset + 1] * 0.587 + pixels[offset + 2] * 0.114
        const alpha = pixels[offset + 3]
        if (alpha > 127 && luminance < 180) byte |= 0x80 >> bit
      }
      bytes.push(byte)
    }
  }
  return {bytes, width, height}
}

export function encoderConfig(config = {}, device = {}) {
  return {
    printerModel: config.printerModel || device.printerModel || null,
    language: device.language || config.language || DEFAULT_CONFIG.language,
    columns: Number(config.columns) || DEFAULT_CONFIG.columns,
    imageMode: config.imageMode || DEFAULT_CONFIG.imageMode,
    feedBeforeCut: Number.isInteger(config.feedBeforeCut) ? config.feedBeforeCut : DEFAULT_CONFIG.feedBeforeCut,
    codepageMapping: device.codepageMapping || config.codepageMapping
  }
}
