import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "row", "query", "live", "empty", "presentCount", "status", "button" ]
  static values = { createUrl: String }

  connect() {
    this.index = 0
    this.onSlash = this.onSlash.bind(this)
    document.addEventListener("keydown", this.onSlash)
    this.activate(this.visibleRows()[0])
  }

  disconnect() {
    document.removeEventListener("keydown", this.onSlash)
  }

  onSlash(event) {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
    const tag = event.target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || event.target.isContentEditable) return
    if (!this.hasQueryTarget) return
    event.preventDefault()
    this.queryTarget.focus()
  }

  filter() {
    const query = this.hasQueryTarget ? this.queryTarget.value.trim().toLowerCase() : ""
    let visible = 0
    this.rowTargets.forEach((row) => {
      const haystack = `${row.dataset.name || ""} ${row.dataset.email || ""}`.toLowerCase()
      const show = query === "" || haystack.includes(query)
      row.hidden = !show
      if (show) visible += 1
    })
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("is-hidden", visible > 0)
    const rows = this.visibleRows()
    if (!rows.includes(this.currentRow())) this.activate(rows[0])
  }

  selectRow(event) {
    this.activate(event.currentTarget)
  }

  toggleButton(event) {
    event.preventDefault()
    event.stopPropagation()
    this.activate(event.currentTarget.closest("[data-roster-target='row']"))
    this.toggle()
  }

  keydown(event) {
    this.activate(event.currentTarget)

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.move(1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.move(-1)
    } else if (event.key === "Enter" || event.key === " ") {
      // Buttons already turn Enter/Space into a click for their own row.
      if (event.target.closest("button")) return
      event.preventDefault()
      this.toggle()
    }
  }

  async toggle() {
    const row = this.currentRow()
    if (!row || row.dataset.busy === "true") return

    const wasPresent = row.dataset.present === "true"
    const previousId = row.dataset.attendanceId
    const previousUrl = row.dataset.deleteUrl
    this.paint(row, !wasPresent, wasPresent ? "" : previousId)
    this.announce(`${row.dataset.name} ${wasPresent ? "removed" : "marked present"}`)
    row.dataset.busy = "true"
    let failureMessage = `Could not update ${row.dataset.name}. Try again.`

    try {
      const response = wasPresent
        ? await this.request(previousUrl, "DELETE")
        : await this.request(this.createUrlValue, "POST", { user_id: row.dataset.userId })

      if (!response.ok) {
        const failure = await response.json()
        failureMessage = failure.error || failureMessage
        throw new Error("request failed")
      }
      const payload = await response.json()
      this.paint(row, payload.present, payload.attendance_id, payload.present_count)
      if (payload.present && payload.attendance_id) {
        row.dataset.deleteUrl = `${this.createUrlValue}/${payload.attendance_id}`
      }
    } catch (_error) {
      this.paint(row, wasPresent, previousId)
      row.dataset.deleteUrl = previousUrl
      row.classList.add("is-error")
      this.announce(failureMessage)
      window.setTimeout(() => row.classList.remove("is-error"), 1600)
    } finally {
      row.dataset.busy = "false"
    }
  }

  move(step) {
    const rows = this.visibleRows()
    if (rows.length === 0) return
    const current = rows.indexOf(this.currentRow())
    const next = rows[(Math.max(current, 0) + step + rows.length) % rows.length]
    this.activate(next)
    next.focus()
  }

  activate(row) {
    this.rowTargets.forEach((entry) => entry.classList.toggle("is-active", entry === row))
    this.index = this.rowTargets.indexOf(row)
  }

  currentRow() {
    return this.rowTargets[this.index] || this.visibleRows()[0]
  }

  visibleRows() {
    return this.rowTargets.filter((row) => !row.hidden)
  }

  paint(row, present, attendanceId, presentCount) {
    row.dataset.present = present ? "true" : "false"
    row.dataset.attendanceId = present ? (attendanceId || "") : ""
    row.classList.toggle("is-present", present)
    const status = row.querySelector("[data-roster-target='status']")
    const button = row.querySelector("[data-roster-target='button']")
    if (status) status.textContent = present ? "Present" : "—"
    if (button) {
      button.textContent = present ? "Remove" : "Mark present"
      button.className = present ? "linkish" : "button-secondary compact"
    }
    if (presentCount != null && this.hasPresentCountTarget) {
      this.presentCountTarget.textContent = presentCount
    } else if (this.hasPresentCountTarget) {
      this.presentCountTarget.textContent = this.rowTargets.filter((entry) => entry.dataset.present === "true").length
    }
  }

  announce(message) {
    if (this.hasLiveTarget) this.liveTarget.textContent = message
  }

  async request(url, method, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const headers = {
      Accept: "application/json",
      "X-CSRF-Token": token || "",
      "X-Requested-With": "XMLHttpRequest"
    }
    const options = { method, headers }
    if (body) {
      headers["Content-Type"] = "application/json"
      options.body = JSON.stringify(body)
    }
    return fetch(url, options)
  }
}
