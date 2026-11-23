import { Controller } from "@hotwired/stimulus"

// Sits on a group of radio buttons and clears the picked one when it is clicked again.
export default class extends Controller {
  connect() {
    this.picked = this.element.querySelector("input:checked")
  }

  toggle(event) {
    if (event.target === this.picked) {
      event.target.checked = false
      this.picked = null
      // Browsers differ on whether clearing a radio here counts as a change, and the
      // unsaved-changes warning needs to hear about it.
      event.target.dispatchEvent(new Event("change", { bubbles: true }))
    } else {
      this.picked = event.target
    }
  }
}
