// Holo shine that follows the pointer, plus a slight tilt. Cards opt in with data-tilt.
// Elements are tracked in a WeakSet (not a data attribute) because Turbolinks restores
// cached pages as fresh DOM nodes without their listeners.
const ready = new WeakSet()
const MAX_TILT = 9 // degrees

export function initCardTilt() {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches

  document.querySelectorAll(".tcg-card[data-tilt]").forEach((card) => {
    if (ready.has(card)) return
    ready.add(card)

    card.addEventListener("pointermove", (event) => {
      if (event.pointerType === "touch") return

      const rect = card.getBoundingClientRect()
      const x = (event.clientX - rect.left) / rect.width
      const y = (event.clientY - rect.top) / rect.height

      card.style.setProperty("--mx", `${(x * 100).toFixed(1)}%`)
      card.style.setProperty("--my", `${(y * 100).toFixed(1)}%`)

      if (!reduceMotion) {
        card.style.setProperty("--ry", `${((x - 0.5) * MAX_TILT * 2).toFixed(2)}deg`)
        card.style.setProperty("--rx", `${((0.5 - y) * MAX_TILT * 2).toFixed(2)}deg`)
      }
    })

    card.addEventListener("pointerleave", () => {
      card.style.removeProperty("--rx")
      card.style.removeProperty("--ry")
    })
  })
}
