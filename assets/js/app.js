// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/breakthrough"
import topbar from "../vendor/topbar"

const hooks = {
  ShareLink: {
    mounted() {
      this.syncUrl()
    },

    syncUrl() {
      const input = this.el.querySelector("#game-share-link")
      const button = this.el.querySelector("#copy-link-button")
      const shareUrl = new URL(this.el.dataset.shareUrl, window.location.origin)

      if (shareUrl.hostname === "localhost" && window.location.hostname !== "localhost") {
        shareUrl.protocol = window.location.protocol
        shareUrl.hostname = window.location.hostname
        shareUrl.port = window.location.port
      } else {
        shareUrl.protocol = window.location.protocol
        shareUrl.hostname = window.location.hostname
        shareUrl.port = window.location.port
      }

      const resolvedUrl = shareUrl.toString()

      if (input) {
        input.value = resolvedUrl
      }

      if (button) {
        button.dataset.copyText = resolvedUrl
      }
    },
  },

  CopyText: {
    mounted() {
      const setLabel = (text) => {
        const label = this.el.querySelector("span")
        if (label) label.textContent = text
      }

      const resetLabel = () => {
        window.setTimeout(() => setLabel("Copy"), 1200)
      }

      const fallbackCopy = (text) => {
        const input = document.querySelector("#game-share-link")
        if (input) {
          input.focus()
          input.select()
          input.setSelectionRange(0, input.value.length)
        }

        const copied = document.execCommand("copy")
        if (copied) {
          setLabel("Copied")
          resetLabel()
        } else {
          setLabel("Copy manually")
        }
      }

      this.handleClick = async () => {
        const target = this.el.dataset.copyTarget
        const input = target ? document.querySelector(target) : null
        const text = input?.value || this.el.dataset.copyText

        try {
          if (!navigator.clipboard || !window.isSecureContext) {
            fallbackCopy(text)
            return
          }

          await navigator.clipboard.writeText(text)
          setLabel("Copied")
          resetLabel()
        } catch (_error) {
          fallbackCopy(text)
        }
      }

      this.el.addEventListener("click", this.handleClick)
    },

    destroyed() {
      this.el.removeEventListener("click", this.handleClick)
    }
  },

  BoardDrag: {
    mounted() {
      this.dragState = null
      this.ghost = null
      this.suppressClick = false

      this.handlePointerDown = (event) => {
        if (event.pointerType === "touch") return

        const square = event.target.closest("button[id^='square-']")
        if (!square || square.disabled) return
        if (square.dataset.ownPiece !== "true" || this.el.dataset.canDrag !== "true") return

        const row = square.dataset.row
        const col = square.dataset.col

        this.dragState = {
          pointerId: event.pointerId,
          fromRow: row,
          fromCol: col,
          dragged: false,
          sourceId: square.id,
        }

        this.pushEvent("select-square", {row, col})
        this.createGhost(square, event)
        square.setPointerCapture?.(event.pointerId)
        event.preventDefault()
      }

      this.handlePointerMove = (event) => {
        if (!this.dragState || this.dragState.pointerId !== event.pointerId) return

        if (!this.dragState.dragged) {
          this.dragState.dragged = true
          this.suppressClick = true
          this.el.classList.add("drag-active")
        }

        this.positionGhost(event.clientX, event.clientY)
      }

      this.handlePointerUp = (event) => {
        if (!this.dragState || this.dragState.pointerId !== event.pointerId) return

        const dragState = this.dragState
        this.resetDrag()

        if (!dragState.dragged) return

        const dropTarget = document.elementFromPoint(event.clientX, event.clientY)?.closest("button[id^='square-']")

        if (!dropTarget || dropTarget.id === dragState.sourceId) return

        this.pushEvent("select-square", {
          row: dropTarget.dataset.row,
          col: dropTarget.dataset.col,
        })
      }

      this.handlePointerCancel = (event) => {
        if (!this.dragState || this.dragState.pointerId !== event.pointerId) return
        this.resetDrag()
      }

      this.handleClickCapture = (event) => {
        if (!this.suppressClick) return

        event.preventDefault()
        event.stopImmediatePropagation()
        this.suppressClick = false
      }

      this.el.addEventListener("pointerdown", this.handlePointerDown)
      this.el.addEventListener("pointermove", this.handlePointerMove)
      this.el.addEventListener("pointerup", this.handlePointerUp)
      this.el.addEventListener("pointercancel", this.handlePointerCancel)
      this.el.addEventListener("click", this.handleClickCapture, true)
    },

    updated() {
      this.el.dataset.canDrag = this.el.querySelector("button[id^='square-']:not([disabled])")
        ? "true"
        : this.el.dataset.canDrag
    },

    destroyed() {
      this.resetDrag()
      this.el.removeEventListener("pointerdown", this.handlePointerDown)
      this.el.removeEventListener("pointermove", this.handlePointerMove)
      this.el.removeEventListener("pointerup", this.handlePointerUp)
      this.el.removeEventListener("pointercancel", this.handlePointerCancel)
      this.el.removeEventListener("click", this.handleClickCapture, true)
    },

    createGhost(square, event) {
      this.destroyGhost()

      const piece = square.querySelector("img")
      if (!piece) return

      this.ghost = piece.cloneNode(true)
      this.ghost.id = "board-drag-ghost"
      this.ghost.classList.add("board-drag-ghost")
      document.body.appendChild(this.ghost)
      this.positionGhost(event.clientX, event.clientY)
    },

    positionGhost(x, y) {
      if (!this.ghost) return

      this.ghost.style.left = `${x}px`
      this.ghost.style.top = `${y}px`
    },

    destroyGhost() {
      if (this.ghost) {
        this.ghost.remove()
        this.ghost = null
      }
    },

    resetDrag() {
      this.destroyGhost()
      this.dragState = null
      this.el.classList.remove("drag-active")
      window.setTimeout(() => {
        this.suppressClick = false
      }, 0)
    },
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
