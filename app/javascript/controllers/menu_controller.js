import { Controller } from "@hotwired/stimulus"

// Sits on a <details> menu and shuts it on Escape or a click anywhere else.
export default class extends Controller {
  close() {
    this.element.open = false
  }

  closeOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
