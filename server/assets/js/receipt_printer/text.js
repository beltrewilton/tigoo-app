// Receipt text uses printable ASCII so ESC/POS code-page defaults cannot
// reinterpret UTF-8 accent bytes. Keep the stored invoice data unchanged.
export function receiptText(value = "") {
  const replacements = {
    "¿": "?", "¡": "!", "º": "o", "ª": "a", "°": "deg",
    "–": "-", "—": "-", "−": "-", "…": "...", "•": "*", "·": ".",
    "‘": "'", "’": "'", "“": '"', "”": '"', "«": '"', "»": '"',
    "×": "x", "€": "EUR", "Æ": "AE", "æ": "ae",
    "Œ": "OE", "œ": "oe", "Ø": "O", "ø": "o", "ß": "ss"
  }
  return String(value ?? "")
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(/[\u00a0\u202f]/g, " ")
    .replace(/[¿¡ºª°–—−…•·‘’“”«»×€ÆæŒœØøß]/g, character => replacements[character])
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
    .replace(/[^\x20-\x7e\t\r\n]/gu, "?")
}
