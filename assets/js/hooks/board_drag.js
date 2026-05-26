const squareSelector = "button[id^='square-']"

const BoardDrag = {
  mounted() {
    this.dragState = null
    this.ghost = null
    this.suppressClick = false

    this.handlePointerDown = (event) => {
      if (event.pointerType === "touch") return

      const square = event.target.closest(squareSelector)
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

      const dropTarget = document.elementFromPoint(event.clientX, event.clientY)?.closest(squareSelector)

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
    this.el.dataset.canDrag = this.el.querySelector(`${squareSelector}:not([disabled])`)
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

    this.ghost = document.createElement("img")
    this.ghost.id = "board-drag-ghost"
    this.ghost.src = piece.currentSrc || piece.src
    this.ghost.alt = ""
    this.ghost.setAttribute("aria-hidden", "true")
    this.ghost.className = "board-drag-ghost"
    this.applyGhostStyle(square.dataset.piece)
    document.body.appendChild(this.ghost)
    this.positionGhost(event.clientX, event.clientY)
  },

  applyGhostStyle(pieceCode) {
    if (pieceCode === "B") {
      this.ghost.style.filter =
        "brightness(0.32) contrast(1.2) saturate(0) drop-shadow(0 1px 0 rgba(255,244,220,0.22))"
    } else {
      this.ghost.style.filter = "drop-shadow(0 1px 1px rgba(0,0,0,0.9))"
    }
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
}

export default BoardDrag
