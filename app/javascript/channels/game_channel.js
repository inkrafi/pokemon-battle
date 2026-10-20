// Online games: when the other player moves (or joins), the server says the board changed and this
// page loads its own view of it. The message carries nothing but a version number.
// After a dropped connection, or when the tab comes back to the front, the page is loaded again
// as well: a message may have been missed in between.
import Turbolinks from "turbolinks"
import consumer from "./consumer"

let subscription = null
let subscribedTo = null

function liveElement() {
  return document.querySelector("[data-live-game]")
}

function refresh() {
  Turbolinks.visit(window.location.href, { action: "replace" })
}

function stop() {
  if (subscription) subscription.unsubscribe()
  subscription = null
  subscribedTo = null
}

function start() {
  const element = liveElement()
  const id = element && element.dataset.liveGame
  if (!id) return stop()
  if (subscribedTo === id) return

  stop()
  subscribedTo = id
  let connectedBefore = false
  subscription = consumer.subscriptions.create({ channel: "GameChannel", id }, {
    connected() {
      if (connectedBefore) refresh()
      connectedBefore = true
    },

    received(data) {
      const page = liveElement()
      if (!page || page.dataset.liveGame !== id || page.dataset.version === data.version) return

      refresh()
    }
  })
}

document.addEventListener("turbolinks:load", start)
document.addEventListener("turbolinks:before-cache", stop)
document.addEventListener("visibilitychange", () => {
  if (!document.hidden && liveElement()) refresh()
})
