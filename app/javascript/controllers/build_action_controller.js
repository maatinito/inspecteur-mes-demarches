import { Controller } from "@hotwired/stimulus"

// Visual feedback during Preview/Build form submission.
// Disables the button and swaps its label for a Bootstrap spinner.
export default class extends Controller {
  start(event) {
    const btn = event.currentTarget
    // Différer au tick suivant : sinon btn.disabled=true dans le handler click
    // annule la soumission du form avant qu'elle ne parte.
    setTimeout(() => {
      btn.disabled = true
      btn.dataset.originalText = btn.textContent.trim()
      btn.innerHTML = '<span class="spinner-border spinner-border-sm me-1" role="status" aria-hidden="true"></span>En cours…'
    }, 0)
  }
}
