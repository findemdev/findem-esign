// The platform's app bar (its workspace menu and credits), framed at the end of the signed-in top bar. The framed page
// says how much room its bar needs, and this element takes exactly that in the row. While a menu is open inside, the frame
// covers what is left of and below the bar, so the menu has room over the page. Only the platform's own origin is listened
// to, and it may only send this tab to an address on that origin. The element is kept across page changes and refreshes
// (data-turbo-permanent), so a refresh never strips the frame it added.
const FROM_BAR = 'findem-studio-app-bar'
const FROM_HOST = 'findem-app-host'

export default class extends HTMLElement {
  connectedCallback () {
    let url

    try {
      url = new URL(this.dataset.src)
    } catch (e) {
      return
    }

    this.barOrigin = url.origin
    this.size = { width: 0, height: 0, open: false }

    this.frame = document.createElement('iframe')
    this.frame.title = this.dataset.title || ''
    this.frame.referrerPolicy = 'origin'
    this.frame.setAttribute('scrolling', 'no')
    this.frame.src = url.href

    window.addEventListener('message', this.onMessage)
    window.addEventListener('resize', this.onResize)
    this.frame.addEventListener('load', this.tellViewport)

    this.place()
    this.append(this.frame)
  }

  disconnectedCallback () {
    window.removeEventListener('message', this.onMessage)
    window.removeEventListener('resize', this.onResize)

    this.frame?.remove()
    this.frame = null
  }

  onMessage = (event) => {
    if (!this.frame || event.origin !== this.barOrigin || event.source !== this.frame.contentWindow) return

    const data = event.data || {}

    if (data.source !== FROM_BAR) return

    if (data.type === 'ready') {
      this.tellViewport()
    } else if (data.type === 'size') {
      this.size = { width: Math.max(0, Number(data.width) || 0), height: Math.max(0, Number(data.height) || 0), open: data.open === true }
      this.place()
    } else if (data.type === 'navigate') {
      this.open(data.href)
    }
  }

  onResize = () => {
    this.tellViewport()
    this.place()
  }

  // The framed page lays out by this window's width, which its own frame never has.
  tellViewport = () => {
    this.frame?.contentWindow?.postMessage({ source: FROM_HOST, type: 'viewport', width: window.innerWidth }, this.barOrigin)
  }

  open (href) {
    let url

    try {
      url = new URL(href)
    } catch (e) {
      return
    }

    if (url.origin === this.barOrigin) window.location.assign(url.href)
  }

  place () {
    const { width, height, open } = this.size
    const style = this.frame.style

    this.style.width = `${width}px`
    this.style.height = `${height}px`
    this.toggleAttribute('data-empty', !width || !height)
    this.toggleAttribute('data-open', open)

    if (open) {
      const rect = this.getBoundingClientRect()

      style.top = `${rect.top}px`
      style.left = '0px'
      style.width = `${rect.right}px`
      style.height = `${Math.max(0, window.innerHeight - rect.top)}px`
    } else {
      style.top = style.left = style.width = style.height = ''
    }
  }
}
