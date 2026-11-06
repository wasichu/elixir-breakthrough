const squareSelector = "button[id^='square-']"

const BoardDrag = {
  mounted() {
    this.dragState = null
    this.ghost = null
    this.suppressClick = false
    this.focusedId = null
    this.syncTabStop()

    this.handleFocus = (event) => {
      const square = event.target.closest(squareSelector)
      if (square) this.setActiveSquare(square)
    }

    this.handleKeyDown = (event) => {
      const square = event.target.closest(squareSelector)
      if (!square) return
      const squares = [...this.el.querySelectorAll(squareSelector)]
      const index = squares.indexOf(square)
      const row = Math.floor(index / 8)
      const col = index % 8
      let destination = index

      switch (event.key) {
        case "ArrowUp": destination = Math.max(0, row - 1) * 8 + col; break
        case "ArrowDown": destination = Math.min(7, row + 1) * 8 + col; break
        case "ArrowLeft": destination = row * 8 + Math.max(0, col - 1); break
        case "ArrowRight": destination = row * 8 + Math.min(7, col + 1); break
        case "Home": destination = event.ctrlKey || event.metaKey ? 0 : row * 8; break
        case "End": destination = event.ctrlKey || event.metaKey ? 63 : row * 8 + 7; break
        case "Escape":
          event.preventDefault()
          this.pushEvent("clear-selection", {})
          return
        default: return
      }

      event.preventDefault()
      this.setActiveSquare(squares[destination])
      squares[destination].focus()
    }

    this.handlePointerDown = (event) => {
      if (event.pointerType === "touch" || event.button !== 0) return
      const square = event.target.closest(squareSelector)
      if (!square || square.getAttribute("aria-disabled") === "true") return
      if (square.dataset.ownPiece !== "true" || this.el.dataset.canDrag !== "true") return
      this.dragState = {
        pointerId: event.pointerId,
        sourceId: square.id,
        startX: event.clientX,
        startY: event.clientY,
        dragged: false,
      }
      square.setPointerCapture?.(event.pointerId)
    }

    this.handlePointerMove = (event) => {
      if (!this.dragState || this.dragState.pointerId !== event.pointerId) return
      if (!this.dragState.dragged) {
        if (Math.hypot(event.clientX - this.dragState.startX, event.clientY - this.dragState.startY) < 4) return
        const square = document.getElementById(this.dragState.sourceId)
        if (!square) return this.resetDrag()
        this.dragState.dragged = true
        this.suppressClick = true
        this.el.classList.add("drag-active")
        if (square.dataset.selected !== "true") {
          this.pushEvent("select-square", {row: square.dataset.row, col: square.dataset.col})
        }
        this.createGhost(square, event)
      }
      this.positionGhost(event.clientX, event.clientY)
    }

    this.handlePointerUp = (event) => {
      if (!this.dragState || this.dragState.pointerId !== event.pointerId) return
      const {dragged, sourceId} = this.dragState
      this.resetDrag()
      if (!dragged) return
      const target = document.elementFromPoint(event.clientX, event.clientY)?.closest(squareSelector)
      if (!target || !this.el.contains(target) || target.id === sourceId) return
      this.pushEvent("select-square", {row: target.dataset.row, col: target.dataset.col})
    }

    this.handlePointerCancel = () => this.resetDrag()
    this.handleClickCapture = (event) => {
      const square = event.target.closest(squareSelector)
      if (square && (this.suppressClick || square.getAttribute("aria-disabled") === "true")) {
        event.preventDefault()
        event.stopImmediatePropagation()
        this.suppressClick = false
      }
    }

    this.el.addEventListener("focusin", this.handleFocus)
    this.el.addEventListener("keydown", this.handleKeyDown)
    this.el.addEventListener("pointerdown", this.handlePointerDown)
    this.el.addEventListener("pointermove", this.handlePointerMove)
    this.el.addEventListener("pointerup", this.handlePointerUp)
    this.el.addEventListener("pointercancel", this.handlePointerCancel)
    this.el.addEventListener("click", this.handleClickCapture, true)
  },

  updated() {
    this.syncTabStop()
    if (this.el.dataset.canDrag !== "true" && this.dragState) this.resetDrag()
  },

  destroyed() {
    this.resetDrag()
    clearTimeout(this.resetTimer)
    this.el.removeEventListener("focusin", this.handleFocus)
    this.el.removeEventListener("keydown", this.handleKeyDown)
    this.el.removeEventListener("pointerdown", this.handlePointerDown)
    this.el.removeEventListener("pointermove", this.handlePointerMove)
    this.el.removeEventListener("pointerup", this.handlePointerUp)
    this.el.removeEventListener("pointercancel", this.handlePointerCancel)
    this.el.removeEventListener("click", this.handleClickCapture, true)
  },

  setActiveSquare(square) {
    this.focusedId = square.id
    this.el.querySelectorAll(squareSelector).forEach((item) => { item.tabIndex = item === square ? 0 : -1 })
  },

  syncTabStop() {
    // LiveView owns the squares; restore only client focus attributes after a patch.
    const active = this.focusedId && document.getElementById(this.focusedId)
    const entry = this.el.querySelector(`#square-${this.el.dataset.entrySquare}`)
    const square = active && this.el.contains(active) ? active : entry || this.el.querySelector(squareSelector)
    if (square) this.setActiveSquare(square)
  },

  createGhost(square, event) {
    this.destroyGhost()
    const piece = square.querySelector("img")
    if (!piece) return
    this.ghost = piece.cloneNode(true)
    this.ghost.id = "board-drag-ghost"
    this.ghost.alt = ""
    this.ghost.setAttribute("aria-hidden", "true")
    this.ghost.className = `board-drag-ghost ${square.dataset.piece === "B" ? "board-pawn-black" : ""}`
    document.body.appendChild(this.ghost)
    this.positionGhost(event.clientX, event.clientY)
  },

  positionGhost(x, y) {
    if (!this.ghost) return
    this.ghost.style.left = `${x}px`
    this.ghost.style.top = `${y}px`
  },

  destroyGhost() {
    this.ghost?.remove()
    this.ghost = null
  },

  resetDrag() {
    this.destroyGhost()
    this.dragState = null
    this.el.classList.remove("drag-active")
    clearTimeout(this.resetTimer)
    this.resetTimer = setTimeout(() => { this.suppressClick = false }, 0)
  },
}

export default BoardDrag
