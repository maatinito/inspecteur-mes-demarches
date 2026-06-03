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
    if (this.workspaceTarget.value) {
      await this.#loadApplications(this.workspaceTarget.value)
    }
  }

  async onWorkspaceChange(event) {
    const wsId = event.target.value
    if (!wsId) {
      this.#reset(this.applicationTarget, "—")
      this.#reset(this.tableTarget, "—")
      return
    }
    await this.#loadApplications(wsId)
    this.#reset(this.tableTarget, "—")
  }

  async onApplicationChange(event) {
    const appId = event.target.value
    if (!appId) {
      this.#reset(this.tableTarget, "—")
      return
    }
    await this.#loadTables(appId)
  }

  async #loadApplications(wsId) {
    const url = `/admin/demarches/${this.demarcheIdValue}/schema/targets/${this.targetTypeValue}/applications/${wsId}`
    const list = await this.#fetchJson(url)
    this.#populate(this.applicationTarget, list, "Sélectionnez une application")
    if (this.applicationTarget.value) {
      await this.#loadTables(this.applicationTarget.value)
    }
  }

  async #loadTables(appId) {
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
    const response = await fetch(`/admin/demarches/${this.demarcheIdValue}/schema/targets/${this.targetTypeValue}/selection`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken,
        'Accept': 'text/vnd.turbo-stream.html'
      },
      body: JSON.stringify(payload)
    })

    // Après update de la sélection, on relance le diff des 3 sections (main_table,
    // avis, blocs) pour qu'elles reflètent la nouvelle cible — sinon l'utilisateur
    // verrait des anciennes infos jusqu'à un reload manuel.
    if (response.ok) {
      this.#reloadSectionFrames()
    }
  }

  #reloadSectionFrames() {
    const id = this.schemaTargetIdValue
    if (!id) return
    ;["main-table-", "avis-", "blocks-"].forEach((prefix) => {
      const frame = document.getElementById(`${prefix}${id}`)
      if (frame && typeof frame.reload === "function") {
        frame.reload()
      }
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
