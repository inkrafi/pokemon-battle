// This file is automatically compiled by Webpack, along with any other files
// present in this directory. You're encouraged to place your actual application logic in
// a relevant structure within app/javascript and only use these pack files to reference
// that code so it'll be compiled.

import Rails from "@rails/ujs"
import Turbolinks from "turbolinks"
import * as ActiveStorage from "@rails/activestorage"
import "channels"

import { initCardTilt } from "../src/card_tilt"
import "../src/nav_toggle"

Rails.start()
Turbolinks.start()
ActiveStorage.start()

// turbolinks:load fires on the first page load and after every Turbolinks visit.
document.addEventListener("turbolinks:load", () => {
  initCardTilt()
})
