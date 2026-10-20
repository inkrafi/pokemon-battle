// Opens and closes the mobile menu. This replaces Bootstrap's JavaScript bundle (about 80KB),
// which was only used for this one toggle. One delegated listener, registered once at load.
document.addEventListener("click", (event) => {
  const toggle = event.target.closest("[data-nav-toggle]")
  if (!toggle) return

  const menu = document.querySelector(toggle.dataset.navToggle)
  if (!menu) return

  const open = menu.classList.toggle("show")
  toggle.setAttribute("aria-expanded", String(open))
  toggle.classList.toggle("collapsed", !open)
})
