import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["workspace", "application", "table"]
  static values = { targetType: String, demarcheId: Number, schemaTargetId: Number }

  connect() {
    this.loadWorkspaces()
  }

  async loadWorkspaces() {
    const url = `/admin/demarches/${this.demarcheIdValue}/schema/targets/${this.targetTypeValue}/workspaces`
    const list = await this.#fetchJson(url)
    this.#populate(this.workspaceTarget, list, "Sélectionnez un workspace")
  }

  async onWorkspaceChange(event) {
    const wsId = event.target.value
    if (!wsId) {
      this.#reset(this.applicationTarget, "—")
      this.#reset(this.tableTarget, "—")
      return
    }
    const url = `/admin/demarches/${this.demarcheIdValue}/schema/targets/${this.targetTypeValue}/applications/${wsId}`
    const list = await this.#fetchJson(url)
    this.#populate(this.applicationTarget, list, "Sélectionnez une application")
    this.#reset(this.tableTarget, "—")
  }

  async onApplicationChange(event) {
    const appId = event.target.value
    if (!appId) {
      this.#reset(this.tableTarget, "—")
      return
    }
    const url = `/admin/demarches/${this.demarcheIdValue}/schema/targets/${this.targetTypeValue}/tables/${appId}`
    const list = await this.#fetchJson(url)
    this.#populate(this.tableTarget, list, "Sélectionnez une table principale")
  }

  async onSelectionChange() {
    const payload = {
      workspace_external_id: this.workspaceTarget.value,
      application_external_id: this.applicationTarget.value,
      main_table_external_id: this.tableTarget.value
    }
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    await fetch(`/admin/demarches/${this.demarcheIdValue}/schema/targets/${this.targetTypeValue}/selection`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken,
        'Accept': 'text/vnd.turbo-stream.html'
      },
      body: JSON.stringify(payload)
    })
  }

  async #fetchJson(url) {
    const res = await fetch(url, { headers: { 'Accept': 'application/json' } })
    return res.ok ? res.json() : []
  }

  #populate(selectEl, items, placeholder) {
    const selectedValue = selectEl.dataset.selectedValue
    selectEl.innerHTML = `<option value="">${placeholder}</option>`
    items.forEach(item => {
      const opt = document.createElement('option')
      opt.value = item.id ?? item.external_id ?? ''
      opt.textContent = item.name ?? item.label ?? `(${opt.value})`
      if (selectedValue && String(opt.value) === String(selectedValue)) opt.selected = true
      selectEl.appendChild(opt)
    })
  }

  #reset(selectEl, placeholder) {
    selectEl.innerHTML = `<option value="">${placeholder}</option>`
  }
}
