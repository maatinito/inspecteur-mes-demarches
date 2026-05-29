import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  switch(event) {
    event.preventDefault()
    const link = event.currentTarget
    const targetId = link.getAttribute("href").substring(1)

    this.element.querySelectorAll("a.nav-link").forEach(l => l.classList.remove("active"))
    link.classList.add("active")

    this.panelTargets.forEach(p => {
      p.classList.toggle("show", p.id === targetId)
      p.classList.toggle("active", p.id === targetId)
    })
  }
}
