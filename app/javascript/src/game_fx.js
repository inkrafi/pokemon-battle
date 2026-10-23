// Game feel for the table: notifications for what happened since this screen was last drawn, a
// banner when the turn changes or the game ends, cards that fly where they went (deck to hand, hand
// to the table, a Knocked Out Pokémon to the discard pile ...), the deck being shuffled, and sound.
//
// The board is drawn again after every move, so nothing here keeps state in memory. What the screen
// last showed (the last log entry, the Pokémon in play and where they were, the hand, the size of
// each pile) is remembered per game and seat in sessionStorage, and the next page compares itself
// with it.
import { play as sound, stopMusic } from "./sound"

const TOAST_GAP = 650 // ms between two notifications
const TOAST_LIFE = 3600
const MAX_TOASTS = 6 // a long turn of the computer is summed up, not replayed in full
const FLIGHT = 520 // ms a card is in the air
const FLIGHT_GAP = 140 // between cards that fly one after another

const KINDS = {
  attack: { icon: "⚔️", title: "Attack!" },
  damage: { icon: "💢", title: "Damage" },
  knockout: { icon: "💥", title: "Knocked Out!" },
  prize: { icon: "🏆", title: "Prize card" },
  coin: { icon: "🪙", title: "Coin flip" },
  condition: { icon: "☠️", title: "Special Condition" },
  heal: { icon: "💚", title: "Healed" },
  evolve: { icon: "✨", title: "Evolution" },
  trainer: { icon: "🎴", title: "Trainer" },
  energy: { icon: "⚡", title: "Energy" },
  bench: { icon: "🔁", title: "Pokémon" },
  draw: { icon: "🂠", title: "Cards" },
  info: { icon: "ℹ️", title: "Game" }
}
// the sound each kind of notification makes
const KIND_SOUNDS = {
  attack: "attack", damage: "hit", knockout: "knockout", prize: "prize", coin: "coin", condition: "condition",
  heal: "heal", evolve: "evolve", trainer: "trainer", energy: "energy", bench: "place"
}
// The viewer's own plain moves need no notification: they just made them.
const QUIET_WHEN_MINE = ["draw", "energy", "bench", "trainer", "end"]
const IMPORTANT = ["knockout", "prize", "attack", "coin"]
const SHUFFLES = /shuffle|searched their deck|draws a new hand/

const reduceMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

function load(key) {
  try {
    return JSON.parse(sessionStorage.getItem(key) || "null")
  } catch (error) {
    return null
  }
}

function save(key, value) {
  try {
    sessionStorage.setItem(key, JSON.stringify(value))
  } catch (error) {
    // without storage every page simply starts fresh
  }
}

const count = (selector) => {
  const element = document.querySelector(selector)
  return element ? Number(element.dataset.count) : null
}

function snapshot(root) {
  const slots = {}
  document.querySelectorAll("[data-fx-slot]").forEach((slot) => {
    const rect = slot.getBoundingClientRect()
    const image = slot.querySelector(".card-thumb img")
    slots[slot.dataset.fxSlot] = {
      damage: Number(slot.dataset.fxDamage),
      hp: Number(slot.dataset.fxHp),
      top: slot.dataset.fxTop,
      energy: Number(slot.dataset.fxEnergy),
      seat: slot.dataset.fxSeat,
      // where it was on the page, so a Pokémon that is gone can still be seen leaving
      rect: [rect.left + window.scrollX, rect.top + window.scrollY, rect.width, Math.min(rect.width * 1.38, rect.height)],
      image: image ? image.currentSrc || image.src : null
    }
  })
  const piles = {}
  ;[0, 1].forEach((seat) => {
    piles[seat] = {
      hand: count(`[data-fx-hand="${seat}"]`),
      deck: count(`[data-fx-deck="${seat}"]`),
      discard: count(`[data-fx-discard="${seat}"]`),
      prizes: count(`[data-fx-prizes="${seat}"]`)
    }
  })
  const hand = [...document.querySelectorAll("[data-fx-card]")].map((card) => card.dataset.fxCard)
  const entries = [...root.querySelectorAll(".game-fx__feed li")]
  const last = entries.length ? Number(entries[entries.length - 1].dataset.n) : 0
  return { last, slots, hand, piles }
}

// ---------------------------------------------------------------- notifications

function toast(root, entry) {
  const kind = KINDS[entry.dataset.kind] || KINDS.info
  const element = document.createElement("div")
  element.className = `toast-note toast-note--${entry.dataset.kind}`
  if (entry.dataset.seat !== "") element.dataset.seat = entry.dataset.seat === root.dataset.fxViewer ? "mine" : "theirs"

  const icon = document.createElement("span")
  icon.className = "toast-note__icon"
  icon.textContent = kind.icon
  const body = document.createElement("span")
  body.className = "toast-note__body"
  const title = document.createElement("strong")
  title.textContent = kind.title
  const text = document.createElement("span")
  text.textContent = entry.textContent
  body.append(title, text)
  element.append(icon, body)

  const stack = root.querySelector(".toasts")
  stack.append(element)
  while (stack.children.length > 4) stack.firstElementChild.remove()
  setTimeout(() => element.classList.add("is-leaving"), TOAST_LIFE)
  setTimeout(() => element.remove(), TOAST_LIFE + 400)
  if (KIND_SOUNDS[entry.dataset.kind]) sound(KIND_SOUNDS[entry.dataset.kind])
}

function banner(root, title, sub, tone) {
  const element = root.querySelector(".turn-banner")
  element.querySelector(".turn-banner__title").textContent = title
  element.querySelector(".turn-banner__sub").textContent = sub || ""
  element.dataset.tone = tone
  element.classList.remove("is-showing")
  void element.offsetWidth // restart the animation
  element.classList.add("is-showing")
}

// ---------------------------------------------------------------- cards in flight

// A card (face up with +image+, face down without) flies from one box to another. The boxes are
// [left, top, width, height] in viewport pixels. +hide+ is kept hidden until the card lands.
function fly(from, to, { image = null, delay = 0, hide = null, spin = 0, fade = false, small = false } = {}) {
  if (!from || !to) return wait(delay)
  if (hide) hide.style.visibility = "hidden"

  const card = document.createElement("div")
  card.className = `flying-card${image ? "" : " flying-card--back"}${small ? " flying-card--small" : ""}`
  if (image) {
    const img = document.createElement("img")
    img.src = image
    img.alt = ""
    card.append(img)
  }
  const [left, top, width, height] = to
  Object.assign(card.style, { left: `${left}px`, top: `${top}px`, width: `${width}px`, height: `${height}px` })
  document.body.append(card)

  const dx = from[0] + from[2] / 2 - (left + width / 2)
  const dy = from[1] + from[3] / 2 - (top + height / 2)
  const scale = Math.max(0.15, from[2] / width)
  const end = fade ? "scale(0.3) rotate(25deg)" : "none"
  const animation = card.animate([
    { transform: `translate(${dx}px, ${dy}px) scale(${scale}) rotate(${spin}deg)`, opacity: fade ? 1 : 0.6 },
    { offset: 0.65, opacity: 1 },
    { transform: end, opacity: fade ? 0 : 1 }
  ], { duration: FLIGHT, delay, easing: "cubic-bezier(0.25, 0.8, 0.3, 1)", fill: "backwards" })

  // The card lands when the animation ends, or after a while in any case: a tab that isn't drawn
  // (in the background, for example) may never finish it, and a hidden card must come back.
  let landed = false
  const land = () => {
    if (landed) return
    landed = true
    card.remove()
    if (hide) {
      hide.style.visibility = ""
      hide.animate([{ transform: "scale(1.08)" }, { transform: "none" }], { duration: 220, easing: "ease-out" })
    }
  }
  setTimeout(land, delay + FLIGHT + 1500)
  return animation.finished.catch(() => {}).then(land)
}

const box = (element) => {
  if (!element) return null
  const rect = element.getBoundingClientRect()
  return [rect.left, rect.top, rect.width, rect.height]
}

// Where a seat's cards come from and go to: the viewer's hand is on the page, the other hand is
// only its count in the mat header.
function handBox(seat, viewer) {
  if (String(seat) === viewer) {
    const hand = document.querySelector("[data-fx-my-hand]")
    if (hand) {
      const rect = hand.getBoundingClientRect()
      return [rect.left + rect.width / 2 - 40, Math.min(rect.top + 40, window.innerHeight - 60), 80, 110]
    }
  }
  return box(document.querySelector(`[data-fx-hand="${seat}"]`))
}

function shuffleDeck(seat) {
  const deck = document.querySelector(`[data-fx-deck="${seat}"]`)
  if (!deck || reduceMotion()) return
  deck.classList.remove("is-shuffling")
  void deck.offsetWidth
  deck.classList.add("is-shuffling")
  deck.addEventListener("animationend", () => deck.classList.remove("is-shuffling"), { once: true })
}

function animateCards(before, viewer, fresh) {
  const motion = !reduceMotion()
  let flights = 0
  const next = () => (flights++) * FLIGHT_GAP

  // the deck is shuffled when the log says so
  const shuffled = new Set(fresh.filter((entry) => SHUFFLES.test(entry.textContent)).map((entry) => entry.dataset.seat))
  shuffled.forEach((seat) => shuffleDeck(seat))
  if (shuffled.size) sound("shuffle")
  const start = shuffled.size && motion ? 700 : 0

  // a Pokémon that left the table: Knocked Out to the discard pile, or back into the hand
  Object.entries(before.slots).forEach(([key, was]) => {
    if (document.querySelector(`[data-fx-slot="${key}"]`) || !motion || !was.rect) return
    const [x, y, width, height] = was.rect
    const from = [x - window.scrollX, y - window.scrollY, width, height]
    const discard = document.querySelector(`[data-fx-discard="${was.seat}"]`)
    const discarded = discard && Number(discard.dataset.count) > (before.piles[was.seat].discard || 0)
    fly(from, from, { image: was.image, delay: start, fade: true, spin: -8 }) // shakes and falls where it stood
    if (discarded) fly(from, box(discard), { image: was.image, delay: start + 250, fade: true, small: true })
  })

  // the viewer's new cards come from the deck (or a Prize card) into the hand
  const myDeck = box(document.querySelector(`[data-fx-deck="${viewer}"]`))
  document.querySelectorAll("[data-fx-card]").forEach((card) => {
    if (before.hand.includes(card.dataset.fxCard) || !motion) return
    const thumb = card.querySelector(".card-thumb")
    const target = box(thumb || card)
    if (target && target[1] < window.innerHeight && target[1] + target[3] > 0) {
      const delay = start + next()
      fly(myDeck, target, { image: thumb && thumb.dataset.cardZoom ? thumb.querySelector("img").src : null, delay, hide: thumb, spin: -14 })
      sound("deal", delay)
    }
  })

  // the other player's hand grows: cards fly face down from their deck
  ;[0, 1].forEach((seat) => {
    if (String(seat) === viewer || !motion) return
    const was = before.piles[seat]
    const grew = Math.min(3, (count(`[data-fx-hand="${seat}"]`) || 0) - (was.hand || 0))
    for (let i = 0; i < grew; i++) {
      const delay = start + next()
      fly(box(document.querySelector(`[data-fx-deck="${seat}"]`)), box(document.querySelector(`[data-fx-hand="${seat}"]`)), { delay, small: true, spin: 10 })
      sound("deal", delay)
    }
  })

  // Prize cards taken fly from the Prize row into the hand
  ;[0, 1].forEach((seat) => {
    const taken = Math.min(3, (before.piles[seat].prizes || 0) - (count(`[data-fx-prizes="${seat}"]`) || 0))
    for (let i = 0; i < taken && motion; i++) {
      fly(box(document.querySelector(`[data-fx-prizes="${seat}"]`)), handBox(seat, viewer), { delay: start + 400 + next(), small: true })
    }
  })

  // Pokémon that came into play, evolved or got Energy: the card comes from its owner's hand
  document.querySelectorAll("[data-fx-slot]").forEach((slot) => {
    const was = before.slots[slot.dataset.fxSlot]
    const seat = slot.dataset.fxSeat
    const thumb = slot.querySelector(".card-thumb")
    const image = thumb && thumb.querySelector("img") ? thumb.querySelector("img").src : null
    if (!motion) return

    if (!was || slot.dataset.fxTop !== was.top) {
      const delay = start + next()
      fly(handBox(seat, viewer), box(thumb || slot), { image, delay, hide: thumb, spin: seat === viewer ? -10 : 10 })
      sound("place", delay + FLIGHT - 80)
    } else if (Number(slot.dataset.fxEnergy) > was.energy) {
      const icons = slot.querySelectorAll(".slot__energy .energy")
      const icon = icons[icons.length - 1]
      if (icon) {
        fly(handBox(seat, viewer), box(icon), { delay: start + next(), hide: icon, small: true })
      }
    }
  })
  return start + flights * FLIGHT_GAP
}

// ---------------------------------------------------------------- the table

function replay(element, className) {
  element.classList.remove(className)
  void element.offsetWidth
  element.classList.add(className)
  element.addEventListener("animationend", () => element.classList.remove(className), { once: true })
}

function floatNumber(slot, text, tone) {
  const number = document.createElement("span")
  number.className = `fx-number fx-number--${tone}`
  number.textContent = text
  slot.append(number)
  number.addEventListener("animationend", () => number.remove(), { once: true })
}

// HP bars start from where they were and run down (or up) to the new value.
function slideHp(slot, before) {
  const bar = slot.querySelector(".slot__hp-bar i")
  if (!bar || !before.hp) return
  const target = bar.style.width
  bar.style.transition = "none"
  bar.style.width = `${Math.max(0, Math.round((1 - before.damage / before.hp) * 100))}%`
  void bar.offsetWidth
  bar.style.transition = ""
  requestAnimationFrame(() => { bar.style.width = target })
}

function animateTable(root, before, attackers, start) {
  const motion = !reduceMotion()

  setTimeout(() => {
    attackers.forEach((seat) => {
      const slot = document.querySelector(`[data-fx-seat="${seat}"][data-fx-active="true"]`)
      if (slot && motion) replay(slot, String(seat) === root.dataset.fxViewer ? "fx-lunge-up" : "fx-lunge-down")
    })
  }, start)

  // the hits land a moment after the attacker moves
  setTimeout(() => {
    document.querySelectorAll("[data-fx-slot]").forEach((slot) => {
      const now = { damage: Number(slot.dataset.fxDamage), top: slot.dataset.fxTop }
      const was = before.slots[slot.dataset.fxSlot]
      if (!was) return

      if (now.damage > was.damage) {
        floatNumber(slot, `-${now.damage - was.damage}`, "hurt")
        if (motion) replay(slot, "fx-hit")
        slideHp(slot, was)
      } else if (now.damage < was.damage) {
        floatNumber(slot, `+${was.damage - now.damage}`, "heal")
        slideHp(slot, was)
      }
      if (now.top !== was.top) setTimeout(() => replay(slot, "fx-evolve"), FLIGHT)
    })
  }, start + (attackers.length ? 320 : 0))
}

// ---------------------------------------------------------------- the first look at a game

// Both decks are shuffled and the opening hand is dealt.
function opening(viewer) {
  if (reduceMotion()) return
  ;[0, 1].forEach((seat) => shuffleDeck(seat))
  sound("shuffle")
  const deck = box(document.querySelector(`[data-fx-deck="${viewer}"]`))
  document.querySelectorAll("[data-fx-card]").forEach((card, index) => {
    const thumb = card.querySelector(".card-thumb")
    const delay = 750 + index * FLIGHT_GAP
    fly(deck, box(thumb || card), { image: thumb && thumb.dataset.cardZoom ? thumb.querySelector("img").src : null, delay, hide: thumb, spin: -14 })
    sound("deal", delay)
  })
}

// ---------------------------------------------------------------- shuffling before a draw

// Drawing a card: the deck is shuffled first, then the move is sent and the card flies to the hand.
// The submit is caught before rails-ujs sends the form, and sent again once the shuffle is done.
const SHUFFLE_BEFORE_DRAW = 750

document.addEventListener("submit", (event) => {
  const form = event.target
  if (!form.querySelector('input[name="type"][value="draw"]') || form.dataset.shuffled) return
  event.preventDefault()
  event.stopImmediatePropagation()
  if (form.dataset.shuffling) return // a second click while the deck is being shuffled
  form.dataset.shuffling = "true"

  const root = document.querySelector("[data-game-fx]")
  const viewer = root ? root.dataset.fxViewer : null
  sound("shuffle")
  if (!reduceMotion()) {
    shuffleDeck(viewer)
    const pile = document.querySelector("[data-fx-my-hand] .deck-pile")
    if (pile) replay(pile, "is-shuffling")
  }

  setTimeout(() => {
    form.dataset.shuffled = "true"
    form.requestSubmit ? form.requestSubmit() : form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
  }, reduceMotion() ? 0 : SHUFFLE_BEFORE_DRAW)
}, true)

// ---------------------------------------------------------------- keeping the place on the page

// A move draws the board again; the page stays scrolled where the player was.
const SCROLL_KEY = "fx-scroll"
document.addEventListener("turbolinks:before-visit", () => {
  if (document.querySelector("[data-game-fx]")) save(SCROLL_KEY, { path: location.pathname, y: window.scrollY, at: Date.now() })
})

function restoreScroll() {
  const kept = load(SCROLL_KEY)
  if (kept && kept.path === location.pathname && Date.now() - kept.at < 15000) window.scrollTo(0, kept.y)
  save(SCROLL_KEY, null)
}

// ---------------------------------------------------------------- putting it together

function run() {
  const root = document.querySelector("[data-game-fx]")
  // Turbolinks shows a cached copy of a page before the fresh one: only the fresh one plays
  if (!root || document.documentElement.hasAttribute("data-turbolinks-preview")) return
  restoreScroll()

  const key = `fx-${root.dataset.gameFx}`
  const viewer = root.dataset.fxViewer
  const now = snapshot(root)
  const before = load(key)
  save(key, now)
  if (!before) return opening(viewer)
  if (!before.piles) before.piles = { 0: {}, 1: {} } // remembered by an older version of this script

  const fresh = [...root.querySelectorAll(".game-fx__feed li")].filter((entry) => Number(entry.dataset.n) > before.last)
  const start = animateCards(before, viewer, fresh)
  if (!fresh.length) return

  const attackers = [...new Set(fresh.filter((entry) => entry.dataset.kind === "attack").map((entry) => entry.dataset.seat))]
  animateTable(root, before, attackers, Math.min(start, 600))

  // the end of the game, or else the start of a turn, gets the banner
  const win = fresh.find((entry) => entry.dataset.kind === "win")
  const turns = fresh.filter((entry) => entry.dataset.kind === "turn")
  const turn = turns[turns.length - 1]
  let delay = 0
  if (win) {
    const lost = win.dataset.title === "Defeat"
    stopMusic()
    banner(root, win.dataset.title, "", lost ? "theirs" : "mine")
    sound(lost ? "defeat" : "victory", 300)
    delay = 1400
  } else if (turn) {
    banner(root, turn.dataset.title, `Turn ${turn.dataset.turn}`, turn.dataset.seat === viewer ? "mine" : "theirs")
    sound("turn")
  }

  let notes = fresh.filter((entry) => {
    const kind = entry.dataset.kind
    if (["turn", "win", "end"].includes(kind)) return false
    return !(entry.dataset.seat === viewer && QUIET_WHEN_MINE.includes(kind))
  })
  // keep the ones that matter most when a lot happened at once
  if (notes.length > MAX_TOASTS) {
    const important = notes.filter((entry) => IMPORTANT.includes(entry.dataset.kind))
    notes = [...important, ...notes.filter((entry) => !important.includes(entry))].slice(0, MAX_TOASTS)
    notes.sort((a, b) => Number(a.dataset.n) - Number(b.dataset.n))
  }
  notes.forEach((entry, index) => setTimeout(() => toast(root, entry), delay + index * TOAST_GAP))
}

document.addEventListener("turbolinks:load", run)
