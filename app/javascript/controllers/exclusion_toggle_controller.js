import { Controller } from "@hotwired/stimulus"

// Toggle l'exclusion d'un champ ou d'un bloc.
// PATCH atomique → Turbo Stream qui replace la section concernée.
export default class extends Controller {
  static values = { url: String }

  async toggle(event) {
    const excluded = !event.target.checked
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.urlValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken,
          'Accept': 'text/vnd.turbo-stream.html'
        },
        body: JSON.stringify({ excluded })
      })

      if (response.ok) {
        const streamHtml = await response.text()
        window.Turbo.renderStreamMessage(streamHtml)
      } else {
        // Rollback visuel en cas d'erreur serveur
        event.target.checked = !event.target.checked
      }
    } catch (_err) {
      // Rollback visuel en cas d'erreur réseau
      event.target.checked = !event.target.checked
    }
  }
}
