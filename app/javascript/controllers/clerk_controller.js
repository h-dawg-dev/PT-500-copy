import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "userButton" ]
  static values = { publishableKey: String }

  connect() {
    this.beforeCache = () => this.unmountUserButton()
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.ready = this.load()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.unmountUserButton()
  }

  async load() {
    if (!this.publishableKeyValue || !this.publishableKeyValue.startsWith("pk_")) return

    await this.ensureClerk()
    await window.Clerk.load({
      signInForceRedirectUrl: window.location.origin,
      signUpForceRedirectUrl: window.location.origin
    })

    // Turbo may have left this page while Clerk loaded.
    if (this.hasUserButtonTarget && window.Clerk.user && this.element.isConnected) {
      const node = this.userButtonTarget
      // A page restored from Turbo's cache still holds a copy of the last button; mounting
      // beside it showed two avatars.
      node.replaceChildren()
      window.Clerk.mountUserButton(node)
      this.userButtonNode = node
    }
  }

  // Runs before Turbo caches the page too, so the saved copy has no button in it.
  unmountUserButton() {
    const node = this.userButtonNode
    if (!node) return

    this.userButtonNode = null
    window.Clerk?.unmountUserButton(node)
    node.replaceChildren()
  }

  // Waits for Clerk first, so a click right after the page opens still signs out.
  async signOut() {
    if (!window.dispatchEvent(new Event("app:before-sign-out", { cancelable: true }))) return
    try {
      await this.ready
      await window.Clerk?.signOut({ redirectUrl: "/" })
    } catch (error) {
      window.dispatchEvent(new Event("app:sign-out-failed"))
      throw error
    }
  }

  async signIn(event) {
    event.preventDefault()
    const fallbackUrl = event.currentTarget.href
    try {
      await this.ready
      if (window.Clerk.user) {
        // Clerk has just written the session cookie; let Rails read it.
        window.location.reload()
      } else {
        await window.Clerk.redirectToSignIn({ redirectUrl: window.location.origin })
      }
    } catch {
      window.location.assign(fallbackUrl)
    }
  }

  ensureClerk() {
    if (window.Clerk) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = "https://cdn.jsdelivr.net/npm/@clerk/clerk-js@5/dist/clerk.browser.js"
      script.async = true
      script.crossOrigin = "anonymous"
      // The browser bundle reads the key when the script executes, before load().
      script.setAttribute("data-clerk-publishable-key", this.publishableKeyValue)
      script.onload = resolve
      script.onerror = reject
      document.head.appendChild(script)
    })
  }
}
