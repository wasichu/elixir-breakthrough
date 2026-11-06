const CopyText = {
  mounted() {
    this.isDestroyed = false
    const setLabel = (text) => {
      if (this.isDestroyed) return
      const label = this.el.querySelector("[data-copy-label]")
      if (label) label.textContent = text
    }

    const originalLabel = this.el.querySelector("[data-copy-label]")?.textContent || "Copy link"
    const resetLabel = () => {
      if (this.isDestroyed) return
      clearTimeout(this.resetTimer)
      this.resetTimer = window.setTimeout(() => setLabel(originalLabel), 1800)
    }

    const fallbackCopy = (text) => {
      const input = document.querySelector("#game-share-link")
      if (input) {
        input.focus()
        input.select()
        input.setSelectionRange(0, input.value.length)
      }

      let copied = false
      try {
        copied = document.execCommand("copy")
      } catch (_error) {
        // Keep the selected link available for manual copying.
      }
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
    this.isDestroyed = true
    clearTimeout(this.resetTimer)
    this.el.removeEventListener("click", this.handleClick)
  },
}

export default CopyText
