// Opens a card picture large in the card viewer (games/_card_zoom) when a card thumbnail is clicked,
// and once for the card drawn at the start of a turn. One listener on the document covers every
// page Turbolinks loads.
function open(thumb, note) {
  const dialog = document.querySelector(".card-zoom")
  if (!dialog || !thumb.dataset.cardZoom) return

  const picture = dialog.querySelector(".card-zoom__picture")
  picture.src = thumb.dataset.cardZoom
  picture.alt = thumb.dataset.cardName
  dialog.querySelector(".card-zoom__name").textContent = thumb.dataset.cardName
  dialog.querySelector(".card-zoom__link").href = thumb.dataset.cardUrl
  dialog.querySelector(".card-zoom__note").hidden = !note
  dialog.showModal()
}

document.addEventListener("click", (event) => {
  const dialog = document.querySelector(".card-zoom")
  if (!dialog) return

  // a click on the backdrop lands on the dialog itself, outside its body
  if (event.target === dialog) return dialog.close()

  const thumb = event.target.closest("[data-card-zoom]")
  if (thumb) open(thumb, false)
})

// The card just drawn is shown once per turn. The page is drawn again after every move, so the
// turn it was shown for is remembered for this tab.
document.addEventListener("turbolinks:load", () => {
  const drawn = document.querySelector("[data-just-drawn]")
  if (!drawn) return

  const key = `drawn-${drawn.dataset.justDrawn}`
  try {
    if (sessionStorage.getItem(key)) return
    sessionStorage.setItem(key, "1")
  } catch (error) {
    // without storage the card is still marked New in the hand
    return
  }
  const thumb = drawn.querySelector("[data-card-zoom]")
  // after the card has flown from the deck into the hand (src/game_fx.js)
  if (thumb) setTimeout(() => open(thumb, true), 700)
})

// don't keep an open viewer in the page Turbolinks caches
document.addEventListener("turbolinks:before-cache", () => {
  const dialog = document.querySelector(".card-zoom[open]")
  if (dialog) dialog.close()
})
