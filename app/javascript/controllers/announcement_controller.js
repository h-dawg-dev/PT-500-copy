import { Controller } from "@hotwired/stimulus"

// U12: shows the points announcement as a modal and records the dismissal however it is closed.
export default class extends Controller {
  static targets = [ "form" ]

  connect() {
    if (!this.element.open) this.element.showModal()
  }

  // U12.4: the Close button. Esc closes the dialog natively; both then fire "close", which runs dismiss.
  close(event) {
    event.preventDefault()
    this.element.close()
  }

  // U12.2: tell the server once so the pop-up does not appear again, then take it out of the page.
  dismiss() {
    if (this.dismissed) return
    this.dismissed = true
    this.send()
    this.element.remove()
  }

  send() {
    // keepalive lets the request finish even if the member navigates away straight after closing.
    return fetch(this.formTarget.action, {
      method: "POST",
      body: new FormData(this.formTarget),
      headers: { Accept: "application/json" },
      credentials: "same-origin",
      keepalive: true
    })
  }
}
