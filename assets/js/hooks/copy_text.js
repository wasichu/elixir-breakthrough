const CopyText = {
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
  },
}

export default CopyText
