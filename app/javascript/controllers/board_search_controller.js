import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "input", "result", "list", "empty", "filter" ]

  connect() {
    this.onSlash = this.onSlash.bind(this)
    document.addEventListener("keydown", this.onSlash)
    this.filterLocal()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onSlash)
  }

  onSlash(event) {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
    const tag = event.target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || event.target.isContentEditable) return
    event.preventDefault()
    if (this.hasInputTarget) this.inputTarget.focus()
  }

  filterLocal() {
    const query = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    let visible = 0

    this.resultTargets.forEach((card) => {
      const fields = JSON.parse(card.dataset.searchFields || "[]")
      const show = query === "" || fields.some((field) => field.toLowerCase().includes(query))
      card.hidden = !show
      if (show) visible += 1
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("is-hidden", visible > 0 || query === "")
    }
    if (this.hasListTarget) {
      this.listTarget.classList.toggle("is-hidden", visible === 0 && query !== "")
    }
  }
}
