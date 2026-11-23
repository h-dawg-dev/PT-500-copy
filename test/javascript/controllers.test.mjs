import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

// Execute the real controllers with a small DOM fixture; no browser or network required.
async function loadController(name) {
  const path = new URL(`../../app/javascript/controllers/${name}_controller.js`, import.meta.url)
  const source = (await readFile(path, "utf8"))
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
  return (await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)).default
}

const Roster = await loadController("roster")
const Board = await loadController("board_search")
const ClerkController = await loadController("clerk")
const Announcement = await loadController("announcement")
const RadioToggle = await loadController("radio_toggle")

test("A second click clears a picked radio and reports the change", () => {
  const radio = (value, checked) => ({
    value, checked, events: [], dispatchEvent(event) { this.events.push(event) }
  })
  const first = radio("yes", true)
  const second = radio("no", false)
  const controller = new RadioToggle()
  controller.element = { querySelector: () => first }
  controller.connect()

  controller.toggle({ target: first })
  assert.equal(first.checked, false)
  assert.equal(first.events[0].type, "change")
  assert.equal(first.events[0].bubbles, true)

  // The browser has already checked whichever radio was just clicked.
  second.checked = true
  controller.toggle({ target: second })
  assert.equal(second.checked, true)

  first.checked = true
  controller.toggle({ target: first })
  assert.equal(first.checked, true)
  assert.equal(first.events.length, 1)

  controller.toggle({ target: first })
  assert.equal(first.checked, false)
})

test("Clerk initializes its browser SDK before loading the session", async () => {
  const previousWindow = globalThis.window
  const previousDocument = globalThis.document
  const key = "pk_test_example"
  const loads = []
  try {
    globalThis.window = { location: { origin: "https://pt500.vercel.app" } }
    globalThis.document = {
      createElement() {
        return { attributes: {}, setAttribute(name, value) { this.attributes[name] = value } }
      },
      head: {
        appendChild(script) {
          // Mirror the browser SDK: it cannot initialize without the script key.
          if (script.attributes["data-clerk-publishable-key"] === key) {
            window.Clerk = { load: async (options) => loads.push(options) }
          }
          script.onload()
        }
      }
    }
    const controller = new ClerkController()
    controller.publishableKeyValue = key
    controller.hasUserButtonTarget = false
    await controller.load()
    assert.equal(loads.length, 1)
    assert.equal(loads[0].signInForceRedirectUrl, window.location.origin)
    assert.equal(loads[0].signUpForceRedirectUrl, window.location.origin)
  } finally {
    globalThis.window = previousWindow
    globalThis.document = previousDocument
  }
})

test("sign-in waits for Clerk and transfers authentication through the SDK", async () => {
  const previousWindow = globalThis.window
  const calls = []
  let ready
  try {
    globalThis.window = {
      location: { origin: "https://pt500-dev.vercel.app" },
      Clerk: { redirectToSignIn: async (options) => calls.push(options) }
    }
    const controller = new ClerkController()
    controller.ready = new Promise((resolve) => { ready = resolve })
    const signIn = controller.signIn({ preventDefault() {}, currentTarget: { href: "https://accounts.example/sign-in" } })
    assert.equal(calls.length, 0)
    ready()
    await signIn
    assert.deepEqual(calls, [{ redirectUrl: "https://pt500-dev.vercel.app" }])
    window.Clerk.user = { id: "existing_member" }
    window.location.reload = () => calls.push("reload")
    await controller.signIn({ preventDefault() {}, currentTarget: { href: "https://accounts.example/sign-in" } })
    assert.equal(calls.at(-1), "reload")
  } finally {
    globalThis.window = previousWindow
  }
})

test("a page restored from Turbo's cache shows one Clerk avatar, and the cached copy keeps none", async () => {
  const previousWindow = globalThis.window
  const previousDocument = globalThis.document
  const listeners = {}
  const mounts = []
  const unmounts = []
  try {
    globalThis.window = {
      location: { origin: "https://pt.example.test" },
      Clerk: {
        user: { id: "member" },
        load: async () => {},
        mountUserButton(node) { node.children.push("live avatar"); mounts.push(node) },
        unmountUserButton(node) { unmounts.push(node) }
      }
    }
    globalThis.document = {
      addEventListener(type, listener) { listeners[type] = listener },
      removeEventListener(type, listener) { if (listeners[type] === listener) delete listeners[type] }
    }
    // Turbo's snapshot of the last page still holds the avatar Clerk rendered there.
    const slot = { children: [ "cached avatar" ], replaceChildren() { this.children = [] } }
    const controller = new ClerkController()
    Object.assign(controller, {
      publishableKeyValue: "pk_test_example", hasUserButtonTarget: true, userButtonTarget: slot,
      element: { isConnected: true }
    })

    controller.connect()
    await controller.ready
    assert.deepEqual(slot.children, [ "live avatar" ])
    assert.equal(mounts.length, 1)

    listeners["turbo:before-cache"]()
    assert.deepEqual(slot.children, [])
    assert.deepEqual(unmounts, [ slot ])

    controller.disconnect()
    assert.equal(listeners["turbo:before-cache"], undefined)
    assert.equal(unmounts.length, 1)
  } finally {
    globalThis.window = previousWindow
    globalThis.document = previousDocument
  }
})

test("Clerk does not mount an avatar on a page Turbo has already left", async () => {
  const previousWindow = globalThis.window
  const mounts = []
  try {
    globalThis.window = {
      location: { origin: "https://pt.example.test" },
      Clerk: { user: { id: "member" }, load: async () => {}, mountUserButton: (node) => mounts.push(node) }
    }
    const controller = new ClerkController()
    Object.assign(controller, {
      publishableKeyValue: "pk_test_example", hasUserButtonTarget: true,
      userButtonTarget: { replaceChildren() {} }, element: { isConnected: false }
    })
    await controller.load()
    assert.equal(mounts.length, 0)
  } finally {
    globalThis.window = previousWindow
  }
})

function classList(...initial) {
  const names = new Set(initial)
  return {
    contains: (name) => names.has(name),
    add: (name) => names.add(name),
    remove: (name) => names.delete(name),
    toggle(name, force) {
      const include = force ?? !names.has(name)
      if (include) names.add(name)
      else names.delete(name)
    }
  }
}

function rosterFixture() {
  const calls = []
  const rows = ["Avery", "Alex", "Sam"].map((name, index) => {
    const status = { textContent: "—" }
    const button = { textContent: "Mark present", className: "button-secondary" }
    const row = {
      dataset: { userId: String(index + 1), name, email: `${name}@example.test`, present: "false", attendanceId: "" },
      classList: classList(), hidden: false,
      focus() { this.focused = true },
      querySelector(selector) { return selector.includes("status") ? status : button },
      closest() { return null }
    }
    button.closest = (selector) => selector === "button" ? button : row
    row.button = button
    return row
  })
  const controller = new Roster()
  Object.assign(controller, {
    rowTargets: rows, index: 0, createUrlValue: "/events/1/attendances",
    hasLiveTarget: false, hasPresentCountTarget: false, hasQueryTarget: true,
    queryTarget: { value: "" }, hasEmptyTarget: true, emptyTarget: { classList: classList("is-hidden") }
  })
  controller.request = async (url, method, body) => {
    calls.push({ url, method, body })
    return { ok: true, json: async () => ({ present: method === "POST", attendance_id: calls.length }) }
  }
  return { controller, rows, calls }
}

function keyEvent(key, row, target = row) {
  return {
    key, currentTarget: row, target, prevented: false,
    preventDefault() { this.prevented = true }, stopPropagation() {}
  }
}

const settle = () => new Promise((resolve) => setImmediate(resolve))

test("Enter on a later roster row changes only that person's attendance", async () => {
  const { controller, rows, calls } = rosterFixture()
  const event = keyEvent("Enter", rows[1])
  controller.keydown(event)
  await settle()
  assert.equal(event.prevented, true)
  assert.equal(calls.length, 1)
  assert.equal(calls[0].body.user_id, "2")
  assert.equal(rows[0].dataset.present, "false")
  assert.equal(rows[1].dataset.present, "true")
})

for (const key of ["Enter", " "]) {
  test(`${JSON.stringify(key)} on a focused button allows exactly one native activation`, async () => {
    const { controller, rows, calls } = rosterFixture()
    const event = keyEvent(key, rows[1], rows[1].button)
    controller.keydown(event)
    assert.equal(event.prevented, false)
    assert.equal(calls.length, 0)
    // The browser's native click follows the key; use its actual click handler.
    controller.toggleButton({ ...event, currentTarget: rows[1].button })
    await settle()
    assert.equal(calls.length, 1)
    assert.equal(calls[0].body.user_id, "2")
    assert.equal(rows[0].dataset.present, "false")
  })
}

test("focus and arrow navigation select the focused row before moving", async () => {
  const { controller, rows, calls } = rosterFixture()
  controller.selectRow({ currentTarget: rows[1] })
  assert.equal(controller.currentRow(), rows[1])
  controller.index = 0 // A stale selection must not override the keyboard target.
  controller.keydown(keyEvent("ArrowDown", rows[1]))
  assert.equal(controller.currentRow(), rows[2])
  assert.equal(rows[2].focused, true)
  controller.keydown(keyEvent(" ", rows[2]))
  await settle()
  assert.equal(calls[0].body.user_id, "3")
})

test("filtering excludes hidden rows from attendance navigation", async () => {
  const { controller, rows, calls } = rosterFixture()
  controller.queryTarget.value = "sam"
  controller.filter()
  assert.deepEqual(controller.visibleRows(), [rows[2]])
  controller.keydown(keyEvent("ArrowUp", rows[2]))
  controller.keydown(keyEvent("Enter", rows[2]))
  await settle()
  assert.equal(calls[0].body.user_id, "3")
  assert.equal(rows[0].dataset.present, "false")
})

function boardFixture() {
  const cards = [
    ["Workshop", "Room 10", "Alex Rivera", "alex@example.test", "Fall 2026", "2026-09-22"],
    ["Social", "Student Center", "Sam Rivera"]
  ].map((fields) => ({ dataset: { searchFields: JSON.stringify(fields) }, hidden: false }))
  const controller = new Board()
  Object.assign(controller, {
    hasInputTarget: true, inputTarget: { value: "" }, resultTargets: cards,
    hasEmptyTarget: true, emptyTarget: { classList: classList("is-hidden") },
    hasListTarget: true, listTarget: { classList: classList() }
  })
  return { controller, cards }
}

test("a rejected attendance removal restores the row and displays the server's correction instructions", async () => {
  const previousWindow = globalThis.window
  try {
    globalThis.window = { setTimeout() {} }
    const { controller, rows } = rosterFixture()
    const row = rows[0]
    Object.assign(row.dataset, { present: "true", attendanceId: "42", deleteUrl: "/events/1/attendances/42" })
    controller.hasLiveTarget = true
    controller.liveTarget = { textContent: "" }
    controller.hasPresentCountTarget = true
    controller.presentCountTarget = { textContent: "1" }
    const message = "This change would leave points below zero. Reverse or offset deductions before removing this credit."
    controller.request = async () => ({ ok: false, json: async () => ({ error: message }) })

    await controller.toggle()

    assert.equal(row.dataset.present, "true")
    assert.equal(row.dataset.attendanceId, "42")
    assert.equal(row.dataset.deleteUrl, "/events/1/attendances/42")
    assert.equal(controller.presentCountTarget.textContent, 1)
    assert.equal(controller.liveTarget.textContent, message)
    assert.equal(row.dataset.busy, "false")
  } finally {
    globalThis.window = previousWindow
  }
})

test("live typing matches full names, emails, terms and dates", () => {
  const { controller, cards } = boardFixture()
  for (const query of ["alex rivera", "alex@example.test", "fall 2026", "2026-09-22"]) {
    controller.inputTarget.value = query
    controller.filterLocal()
    assert.equal(cards[0].hidden, false)
    assert.equal(cards[1].hidden, true)
  }
})

test("live search does not match across separate fields, and clearing restores cards", () => {
  const { controller, cards } = boardFixture()
  controller.inputTarget.value = "Workshop Room"
  controller.filterLocal()
  assert.equal(cards.every((card) => card.hidden), true)
  assert.equal(controller.emptyTarget.classList.contains("is-hidden"), false)
  assert.equal(controller.listTarget.classList.contains("is-hidden"), true)
  controller.inputTarget.value = ""
  controller.filterLocal()
  assert.equal(cards.some((card) => card.hidden), false)
  assert.equal(controller.emptyTarget.classList.contains("is-hidden"), true)
  assert.equal(controller.listTarget.classList.contains("is-hidden"), false)
})

// U12: the pop-up announcing officer changes to a member's points.
function announcementFixture({ open = false } = {}) {
  const calls = []
  const controller = new Announcement()
  const dialog = {
    open,
    removed: false,
    showModal() { calls.push("showModal"); this.open = true },
    // A native dialog fires "close" once it shuts, whether from close() or the Esc key.
    close() { calls.push("close"); this.open = false; controller.dismiss() },
    remove() { this.removed = true }
  }
  Object.assign(controller, { element: dialog, formTarget: { action: "/announcement_dismissal" } })
  controller.send = () => calls.push("send")
  return { controller, dialog, calls }
}

test("U12.4: the announcement opens as a modal, so focus stays inside it", () => {
  const { controller, dialog, calls } = announcementFixture()
  controller.connect()
  assert.deepEqual(calls, ["showModal"])
  assert.equal(dialog.open, true)
})

test("U12.4: an announcement already open (restored by Turbo) is not opened twice", () => {
  const { controller, calls } = announcementFixture({ open: true })
  controller.connect()
  assert.deepEqual(calls, [])
})

test("U12.4: the Close button closes the pop-up and records the dismissal", () => {
  const { controller, dialog, calls } = announcementFixture()
  controller.connect()
  const event = { prevented: false, preventDefault() { this.prevented = true } }
  controller.close(event)
  assert.equal(event.prevented, true)
  assert.deepEqual(calls, ["showModal", "close", "send"])
  assert.equal(dialog.removed, true)
})

test("U12.4: the Esc key closes the pop-up and records the dismissal", () => {
  const { controller, dialog, calls } = announcementFixture()
  controller.connect()
  // The browser closes the dialog itself on Esc and then fires "close".
  dialog.open = false
  controller.dismiss()
  assert.deepEqual(calls, ["showModal", "send"])
  assert.equal(dialog.removed, true)
})

test("U12.2: the dismissal is sent only once", () => {
  const { controller, calls } = announcementFixture()
  controller.dismiss()
  controller.dismiss()
  assert.equal(calls.filter((call) => call === "send").length, 1)
})

test("U12.2: the dismissal posts the shown changes to the server and survives leaving the page", async () => {
  const previousFetch = globalThis.fetch
  const previousFormData = globalThis.FormData
  const requests = []
  try {
    globalThis.FormData = class { constructor(form) { this.form = form } }
    globalThis.fetch = async (url, options) => requests.push({ url, options })
    const controller = new Announcement()
    controller.formTarget = { action: "/announcement_dismissal" }
    await controller.send()
    assert.equal(requests.length, 1)
    assert.equal(requests[0].url, "/announcement_dismissal")
    assert.equal(requests[0].options.method, "POST")
    assert.equal(requests[0].options.body.form, controller.formTarget)
    assert.equal(requests[0].options.headers.Accept, "application/json")
    assert.equal(requests[0].options.keepalive, true)
  } finally {
    globalThis.fetch = previousFetch
    globalThis.FormData = previousFormData
  }
})

const UnsavedChanges = await loadController("unsaved_changes")

function unsavedFixture(current = { "user[major]": "Biology", "questionnaire[email_opt_in]": "" }) {
  const previousWindow = globalThis.window
  const previousDocument = globalThis.document
  const previousFormData = globalThis.FormData
  const listeners = new Map()
  const documentListeners = new Map()
  const controller = new UnsavedChanges()
  const fields = { ...current }
  const confirmations = []
  globalThis.window = {
    addEventListener(name, callback) { listeners.set(name, callback) },
    removeEventListener(name) { listeners.delete(name) },
    confirm(message) { confirmations.push(message); return false },
    setTimeout(callback) { this.timeout = callback; return 1 }, clearTimeout() {}
  }
  globalThis.document = {
    addEventListener(name, callback) { documentListeners.set(name, callback) },
    removeEventListener(name) { documentListeners.delete(name) }
  }
  globalThis.FormData = class { entries() { return Object.entries(fields) } }
  Object.assign(controller, {
    element: {}, bannerTarget: { hidden: true },
    savedValue: { "user[major]": "Biology", "questionnaire[email_opt_in]": "" }
  })
  controller.connect()
  return {
    controller, fields, listeners, documentListeners, confirmations,
    restore() {
      controller.disconnect()
      globalThis.window = previousWindow
      globalThis.document = previousDocument
      globalThis.FormData = previousFormData
    }
  }
}

test("unsaved banner and unload protection appear only for changed form values and clear on revert", () => {
  const fixture = unsavedFixture()
  try {
    const { controller, fields, listeners } = fixture
    assert.equal(controller.bannerTarget.hidden, true)
    assert.equal(listeners.has("beforeunload"), false)
    fields["user[major]"] = "Kinesiology"
    controller.refresh()
    assert.equal(controller.bannerTarget.hidden, false)
    const event = { preventDefault() { this.prevented = true } }
    listeners.get("beforeunload")(event)
    assert.equal(event.prevented, true)
    assert.equal(event.returnValue, "You have unsaved changes.")
    fields["user[major]"] = "Biology"
    controller.refresh()
    assert.equal(controller.bannerTarget.hidden, true)
    assert.equal(listeners.has("beforeunload"), false)
    fields["questionnaire[email_opt_in]"] = "yes"
    controller.refresh()
    assert.equal(controller.dirty, true)
  } finally { fixture.restore() }
})

test("failed saves compare the preserved inputs to the persisted baseline, ignoring form tokens", () => {
  const fixture = unsavedFixture({ "user[major]": "Attempted edit", "questionnaire[email_opt_in]": "", authenticity_token: "changed-token" })
  try {
    assert.equal(fixture.controller.dirty, true)
    fixture.fields["user[major]"] = "Biology"
    fixture.controller.refresh()
    assert.equal(fixture.controller.dirty, false)
  } finally { fixture.restore() }
})

test("valid saving does not prompt, and returning from browser history restores dirty protection", () => {
  const fixture = unsavedFixture({ "user[major]": "Kinesiology", "questionnaire[email_opt_in]": "yes" })
  try {
    const event = { preventDefault() { this.prevented = true } }
    fixture.controller.submit()
    fixture.controller.beforeUnload(event)
    assert.equal(event.prevented, undefined)
    fixture.listeners.get("pageshow")()
    fixture.controller.beforeUnload(event)
    assert.equal(event.prevented, true)
    assert.equal(fixture.controller.bannerTarget.hidden, false)
  } finally { fixture.restore() }
})

test("canceling sign-out stops the provider before it discards the member's session", () => {
  const fixture = unsavedFixture({ "user[major]": "Kinesiology", "questionnaire[email_opt_in]": "" })
  try {
    const event = {
      target: { closest() { return {} } },
      preventDefault() { this.prevented = true },
      stopImmediatePropagation() { this.stopped = true }
    }
    fixture.controller.signOut(event)
    assert.equal(event.prevented, true)
    assert.equal(event.stopped, undefined)
    assert.equal(fixture.confirmations.length, 1)
    window.confirm = () => true
    fixture.controller.signOut({ ...event, prevented: false, stopped: false })
    const unload = { preventDefault() { this.prevented = true } }
    fixture.controller.beforeUnload(unload)
    assert.equal(unload.prevented, undefined)
    fixture.listeners.get("app:sign-out-failed")()
    fixture.controller.beforeUnload(unload)
    assert.equal(unload.prevented, true)
  } finally { fixture.restore() }
})

test("leaving an unchanged form needs no warning and controller listeners are cleaned up", () => {
  const fixture = unsavedFixture()
  try {
    fixture.controller.signOut({ target: { closest() { return {} } } })
    assert.equal(fixture.confirmations.length, 0)
    fixture.controller.disconnect()
    assert.equal(fixture.listeners.size, 0)
    assert.equal(fixture.documentListeners.size, 0)
  } finally { fixture.restore() }
})

test("the Clerk sign-out boundary honors cancellation before revoking the session", async () => {
  const previousWindow = globalThis.window
  const calls = []
  try {
    globalThis.window = {
      dispatchEvent(event) { calls.push(event.type); return event.type !== "app:before-sign-out" },
      Clerk: { signOut: async () => calls.push("provider sign-out") }
    }
    const controller = new ClerkController()
    controller.ready = Promise.resolve()
    await controller.signOut()
    assert.deepEqual(calls, ["app:before-sign-out"])

    window.dispatchEvent = (event) => { calls.push(event.type); return true }
    window.Clerk.signOut = async () => { throw new Error("Provider unavailable") }
    await assert.rejects(controller.signOut(), /Provider unavailable/)
    assert.equal(calls.at(-1), "app:sign-out-failed")
  } finally { globalThis.window = previousWindow }
})

test("in-app links show a discard dialog; staying retains edits and leaving avoids a second prompt", () => {
  const fixture = unsavedFixture({ "user[major]": "Kinesiology", "questionnaire[email_opt_in]": "" })
  const assigned = []
  try {
    const controller = fixture.controller
    window.location = { href: "https://pts.example/profile", origin: "https://pts.example", pathname: "/profile", search: "", assign: (url) => assigned.push(url) }
    const dialog = { open: false, showModal() { this.open = true }, close() { this.open = false; controller.clearDestination() } }
    controller.dialogTarget = dialog
    const link = { href: "https://pts.example/", target: "", hasAttribute() { return false } }
    const event = { button: 0, target: { closest() { return link } }, preventDefault() { this.prevented = true } }
    controller.linkClick(event)
    assert.equal(event.prevented, true)
    assert.equal(dialog.open, true)
    controller.keepEditing()
    assert.equal(dialog.open, false)
    assert.equal(controller.dirty, true)
    assert.deepEqual(assigned, [])
    controller.linkClick({ ...event, defaultPrevented: false })
    const major = { name: "user[major]", type: "text", value: "Kinesiology" }
    controller.element.elements = [major]
    controller.discard()
    assert.equal(major.value, "Biology")
    assert.equal(controller.dirty, false)
    assert.deepEqual(assigned, ["https://pts.example/"])
    const unload = { preventDefault() { this.prevented = true } }
    controller.beforeUnload(unload)
    assert.equal(unload.prevented, undefined)
  } finally { fixture.restore() }
})

test("review/save anchors and new-tab clicks do not interrupt editing", () => {
  const fixture = unsavedFixture({ "user[major]": "Kinesiology", "questionnaire[email_opt_in]": "" })
  try {
    window.location = { href: "https://pts.example/profile", origin: "https://pts.example", pathname: "/profile", search: "" }
    const anchor = { href: "https://pts.example/profile#information-save", target: "", hasAttribute() { return false } }
    const event = { button: 0, target: { closest() { return anchor } }, preventDefault() { this.prevented = true } }
    fixture.controller.linkClick(event)
    assert.equal(event.prevented, undefined)
    anchor.href = "https://pts.example/events"
    fixture.controller.linkClick({ ...event, ctrlKey: true })
    assert.equal(event.prevented, undefined)
  } finally { fixture.restore() }
})
