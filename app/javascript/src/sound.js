// Sound effects and background music for the game table, all made with the Web Audio API: there
// are no audio files. Browsers only let a page make sound after the visitor has clicked or pressed
// a key, so nothing plays before that. Moves are Turbolinks visits, so the audio (and the music)
// carries on from one move to the next.
//
// Whether sound and music are on is a choice of this browser, kept in localStorage.

const PREFS = { sound: "pkm-sound", music: "pkm-music" }
const SFX_VOLUME = 0.5
const MUSIC_VOLUME = 0.16

let ctx = null
let sfxBus = null
let musicBus = null
let noiseBuffer = null

function pref(name) {
  try {
    return localStorage.getItem(PREFS[name]) !== "off"
  } catch (error) {
    return true
  }
}

function setPref(name, on) {
  try {
    localStorage.setItem(PREFS[name], on ? "on" : "off")
  } catch (error) {
    // the choice then lasts until the page is closed
  }
}

function audio() {
  if (ctx) return ctx
  const AudioContext = window.AudioContext || window.webkitAudioContext
  if (!AudioContext) return null

  ctx = new AudioContext()
  const master = ctx.createDynamicsCompressor()
  master.connect(ctx.destination)
  sfxBus = ctx.createGain()
  sfxBus.gain.value = SFX_VOLUME
  sfxBus.connect(master)
  musicBus = ctx.createGain()
  musicBus.gain.value = 0
  musicBus.connect(master)

  noiseBuffer = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate)
  const data = noiseBuffer.getChannelData(0)
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1
  return ctx
}

const ready = () => ctx && ctx.state === "running"

// ---------------------------------------------------------------- building blocks

// One note. +slide+ glides the pitch to another frequency over the note.
function tone(freq, duration, { type = "square", volume = 0.3, delay = 0, slide = null, bus = sfxBus, attack = 0.005 } = {}) {
  const start = ctx.currentTime + delay
  const osc = ctx.createOscillator()
  const gain = ctx.createGain()
  osc.type = type
  osc.frequency.setValueAtTime(freq, start)
  if (slide) osc.frequency.exponentialRampToValueAtTime(slide, start + duration)
  gain.gain.setValueAtTime(0.0001, start)
  gain.gain.exponentialRampToValueAtTime(volume, start + attack)
  gain.gain.exponentialRampToValueAtTime(0.0001, start + duration)
  osc.connect(gain).connect(bus)
  osc.start(start)
  osc.stop(start + duration + 0.02)
}

// A burst of filtered noise: swishes, thuds, hits and the hi-hat of the music.
function noise(duration, { filter = "bandpass", freq = 2000, sweep = null, q = 1, volume = 0.3, delay = 0, bus = sfxBus } = {}) {
  const start = ctx.currentTime + delay
  const source = ctx.createBufferSource()
  source.buffer = noiseBuffer
  const shape = ctx.createBiquadFilter()
  shape.type = filter
  shape.Q.value = q
  shape.frequency.setValueAtTime(freq, start)
  if (sweep) shape.frequency.exponentialRampToValueAtTime(sweep, start + duration)
  const gain = ctx.createGain()
  gain.gain.setValueAtTime(volume, start)
  gain.gain.exponentialRampToValueAtTime(0.0001, start + duration)
  source.connect(shape).connect(gain).connect(bus)
  source.start(start, Math.random() * 0.5)
  source.stop(start + duration + 0.02)
}

const notes = (list, step, options) => list.forEach((freq, i) => tone(freq, options.length || step * 1.6, { ...options, delay: (options.delay || 0) + i * step }))

// ---------------------------------------------------------------- the effects

const EFFECTS = {
  click: () => tone(1400, 0.035, { volume: 0.06 }),
  deal: () => noise(0.16, { freq: 1800, sweep: 6000, volume: 0.22 }),
  place: () => { tone(150, 0.14, { type: "sine", slide: 60, volume: 0.5 }); noise(0.06, { filter: "lowpass", freq: 900, volume: 0.2 }) },
  shuffle: () => { for (let i = 0; i < 14; i++) noise(0.035, { filter: "highpass", freq: 2500 + Math.random() * 2000, volume: 0.16, delay: i * 0.05 }) },
  attack: () => {
    noise(0.28, { freq: 500, sweep: 3500, q: 2, volume: 0.3 })
    tone(190, 0.2, { slide: 55, volume: 0.32, delay: 0.24 })
    noise(0.12, { filter: "lowpass", freq: 1400, volume: 0.35, delay: 0.24 })
  },
  hit: () => { tone(320, 0.16, { slide: 110, volume: 0.22 }); noise(0.08, { filter: "lowpass", freq: 1600, volume: 0.25 }) },
  knockout: () => notes([523, 392, 311, 196], 0.11, { type: "square", volume: 0.18, length: 0.16 }),
  prize: () => { tone(988, 0.1, { type: "square", volume: 0.12 }); tone(1319, 0.38, { type: "square", volume: 0.12, delay: 0.09 }) },
  coin: () => { tone(1568, 0.06, { type: "triangle", volume: 0.25 }); tone(2093, 0.3, { type: "triangle", volume: 0.25, delay: 0.06 }) },
  condition: () => tone(330, 0.35, { type: "sawtooth", slide: 210, volume: 0.1 }),
  heal: () => notes([523, 659, 784, 1047], 0.07, { type: "sine", volume: 0.2, length: 0.2 }),
  evolve: () => { tone(220, 0.7, { type: "triangle", slide: 880, volume: 0.25 }); notes([1047, 1319, 1568], 0.08, { type: "sine", volume: 0.12, delay: 0.55, length: 0.25 }) },
  energy: () => tone(700, 0.14, { slide: 1800, volume: 0.12 }),
  trainer: () => { noise(0.1, { freq: 3000, volume: 0.15 }); tone(660, 0.12, { type: "triangle", volume: 0.15, delay: 0.05 }) },
  turn: () => { tone(784, 0.16, { type: "triangle", volume: 0.25 }); tone(1047, 0.35, { type: "triangle", volume: 0.25, delay: 0.14 }) },
  victory: () => { notes([523, 659, 784], 0.12, { type: "square", volume: 0.14, length: 0.14 }); tone(1047, 0.9, { type: "square", volume: 0.14, delay: 0.36 }) },
  defeat: () => notes([392, 349, 311, 262], 0.22, { type: "triangle", volume: 0.25, length: 0.4 })
}

export function play(name, delay = 0) {
  if (!pref("sound") || !audio() || !ready() || !EFFECTS[name]) return
  if (delay) return setTimeout(() => play(name), delay)
  EFFECTS[name]()
}

// ---------------------------------------------------------------- the music
// An original loop in C major (C, Am, F, G): a bass line, a soft arpeggio and a hi-hat, scheduled a
// little ahead of time so it keeps steady while the page works.

const BPM = 112
const STEP = 60 / BPM / 4 // a sixteenth note
const CHORDS = [
  [130.81, [261.63, 329.63, 392.0, 523.25]], // C
  [110.0, [220.0, 261.63, 329.63, 440.0]], // Am
  [87.31, [174.61, 220.0, 261.63, 349.23]], // F
  [98.0, [196.0, 246.94, 293.66, 392.0]] // G
]
const ARP = [0, 1, 2, 3, 2, 1, 2, 3, 0, 2, 1, 3, 2, 1, 0, 1]
const BASS = [1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0]

let musicTimer = null
let nextTime = 0
let step = 0

function scheduleMusic() {
  while (nextTime < ctx.currentTime + 0.25) {
    const [bass, chord] = CHORDS[Math.floor(step / 16) % CHORDS.length]
    const beat = step % 16
    const opts = { bus: musicBus, delay: nextTime - ctx.currentTime }
    if (BASS[beat]) tone(bass, STEP * 1.8, { ...opts, type: "triangle", volume: 0.5 })
    tone(chord[ARP[beat]] * 2, STEP * 0.9, { ...opts, type: "square", volume: 0.07 })
    if (beat % 2 === 0) noise(0.03, { ...opts, filter: "highpass", freq: 7000, volume: beat % 4 === 0 ? 0.08 : 0.04 })
    nextTime += STEP
    step++
  }
}

function startMusic() {
  if (musicTimer || !pref("music") || !audio() || !ready()) return
  nextTime = ctx.currentTime + 0.05
  musicBus.gain.cancelScheduledValues(ctx.currentTime)
  musicBus.gain.setTargetAtTime(MUSIC_VOLUME, ctx.currentTime, 0.6)
  musicTimer = setInterval(scheduleMusic, 60)
  scheduleMusic()
}

export function stopMusic() {
  if (!musicTimer) return
  clearInterval(musicTimer)
  musicTimer = null
  musicBus.gain.setTargetAtTime(0, ctx.currentTime, 0.2)
}

// ---------------------------------------------------------------- page wiring

// music plays at the table while a game is on
const onGamePage = () => document.querySelector("[data-game-fx]:not([data-fx-finished])") !== null

function updateButtons() {
  document.querySelectorAll("[data-sound-toggle]").forEach((button) => {
    const on = pref(button.dataset.soundToggle)
    button.setAttribute("aria-pressed", String(on))
    button.classList.toggle("is-off", !on)
  })
}

// The first click or key press anywhere wakes the audio up.
function unlock() {
  if (!audio()) return
  ctx.resume().then(() => { if (onGamePage()) startMusic() })
}
document.addEventListener("pointerdown", unlock, { capture: true })
document.addEventListener("keydown", unlock, { capture: true })

document.addEventListener("click", (event) => {
  const toggle = event.target.closest("[data-sound-toggle]")
  if (toggle) {
    const name = toggle.dataset.soundToggle
    setPref(name, !pref(name))
    updateButtons()
    if (name === "music") pref("music") ? startMusic() : stopMusic()
    if (name === "sound") play("click")
    return
  }
  if (event.target.closest(".board-layout button, .board-layout summary, .setup button")) play("click")
})

document.addEventListener("turbolinks:load", () => {
  updateButtons()
  onGamePage() ? startMusic() : stopMusic()
})
