import { Controller } from "@hotwired/stimulus"

// The editor uses native navigation so browser Back, reload, external links and
// tab closing all share the browser's built-in beforeunload protection.
export default class extends Controller {
  static targets = [ "banner", "dialog" ]
  static values = { saved: Object }

  connect() {
    this.beforeUnload = this.beforeUnload.bind(this)
    this.pageShow = this.pageShow.bind(this)
    this.signOut = this.signOut.bind(this)
    this.linkClick = this.linkClick.bind(this)
    window.addEventListener("pageshow", this.pageShow)
    window.addEventListener("app:before-sign-out", this.signOut)
    window.addEventListener("app:sign-out-failed", this.pageShow)
    document.addEventListener("click", this.linkClick, true)
    this.refresh()
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.beforeUnload)
    window.removeEventListener("pageshow", this.pageShow)
    window.removeEventListener("app:before-sign-out", this.signOut)
    window.removeEventListener("app:sign-out-failed", this.pageShow)
    document.removeEventListener("click", this.linkClick, true)
  }

  refresh() {
    const current = Object.fromEntries(new FormData(this.element).entries())
    this.dirty = Object.entries(this.savedValue).some(([name, value]) => String(current[name] ?? "") !== String(value ?? ""))
    this.bannerTarget.hidden = !this.dirty
    window.removeEventListener("beforeunload", this.beforeUnload)
    if (this.dirty) window.addEventListener("beforeunload", this.beforeUnload)
  }

  beforeUnload(event) {
    if (!this.dirty || this.leaving) return
    event.preventDefault()
    event.returnValue = "You have unsaved changes."
  }

  submit() {
    // Native submit fires only after browser validation succeeds.
    this.leaving = true
  }

  pageShow() {
    this.leaving = false
    this.refresh()
  }

  signOut(event) {
    if (!this.dirty) return
    if (!window.confirm("You have unsaved changes. Sign out without saving?")) {
      event.preventDefault()
      return
    }
    this.leaving = true
  }

  linkClick(event) {
    if (!this.dirty || this.leaving || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    const link = event.target.closest("a[href]")
    if (!link || link.hasAttribute("download") || (link.target && link.target !== "_self")) return
    const destination = new URL(link.href, window.location.href)
    if (![ "http:", "https:" ].includes(destination.protocol)) return
    if (destination.hash && destination.origin === window.location.origin && destination.pathname === window.location.pathname && destination.search === window.location.search) return

    event.preventDefault()
    this.pendingUrl = destination.href
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  keepEditing() {
    this.dialogTarget.close()
  }

  discard() {
    const destination = this.pendingUrl
    if (!destination) return
    // A browser history cache must not bring back a draft explicitly discarded.
    for (const field of Array.from(this.element.elements || [])) {
      if (!Object.hasOwn(this.savedValue, field.name)) continue
      if (field.type === "radio") field.checked = field.value === this.savedValue[field.name]
      else field.value = this.savedValue[field.name]
    }
    this.dirty = false
    this.bannerTarget.hidden = true
    this.leaving = true
    this.dialogTarget.close()
    window.location.assign(destination)
  }

  clearDestination() {
    this.pendingUrl = null
  }
}
