const ShareLink = {
  mounted() {
    this.syncUrl()
  },

  syncUrl() {
    const input = this.el.querySelector("#game-share-link")
    const button = this.el.querySelector("#copy-link-button")
    const shareUrl = new URL(this.el.dataset.shareUrl, window.location.origin)

    shareUrl.protocol = window.location.protocol
    shareUrl.hostname = window.location.hostname
    shareUrl.port = window.location.port

    const resolvedUrl = shareUrl.toString()

    if (input) {
      input.value = resolvedUrl
    }

    if (button) {
      button.dataset.copyText = resolvedUrl
    }
  },
}

export default ShareLink
