# Builder Schema — Diff & Exclusion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Étendre le builder Slice 1 avec un affichage diff-only au load (Turbo Frame lazy) + exclusion persistante de champs (1 niveau pour la table principale, 2 niveaux pour les blocs).

**Architecture:** Nouveau service `SchemaBuilders::Differ` qui compare descripteurs MD vs schéma cible et retourne 4 collections (to_add / to_modify / ok / excluded). Trois colonnes JSONB sur les modèles existants stockent les exclusions. Vues HAML avec Turbo Frame lazy par section + checkboxes qui PATCH atomiquement et renvoient un Turbo Stream re-rendant la section. Build modifié pour filtrer les exclus.

**Tech Stack:** Rails 7.2.3, Ruby 3.4.4, Hotwire (Turbo 8 + Stimulus), HAML, RSpec + FactoryBot, PostgreSQL jsonb.

**Branche:** `feature/ui-refonte` (continue après le Slice 1).

**Spec source:** `docs/superpowers/specs/2026-05-29-builder-diff-exclusion-design.md`.

## Conventions

- TDD discipliné : Red → Green → Commit. Tests d'abord.
- 1 commit par tâche. Messages en français, format conventional commits.
- `bundle exec rubocop -A` + `bundle exec rake lint` avant chaque commit Ruby/SCSS.
- Push au fil de l'eau sur `feature/ui-refonte` (autonomie autorisée).

---

## Phase A — Data layer (1-2 jours)

### Task A1 : Migration `excluded_field_ids` sur `schema_targets`

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_excluded_field_ids_to_schema_targets.rb`

- [ ] **Step 1: Générer**

```bash
bin/rails generate migration AddExcludedFieldIdsToSchemaTargets
```

- [ ] **Step 2: Éditer**

```ruby
class AddExcludedFieldIdsToSchemaTargets < ActiveRecord::Migration[7.2]
  def change
    add_column :schema_targets, :excluded_field_ids, :jsonb, default: [], null: false
    add_column :schema_targets, :excluded_block_descriptor_ids, :jsonb, default: [], null: false
  end
end
```

Note : on combine les 2 colonnes dans la même migration parce qu'elles concernent la même table et la même feature. Évite un commit séparé inutile.

- [ ] **Step 3: Migrer**

```bash
bin/rails db:migrate RAILS_ENV=development
bin/rails db:migrate RAILS_ENV=test
```

- [ ] **Step 4: Commit**

```bash
git add db/
git commit -m "feat(refonte): excluded_field_ids + excluded_block_descriptor_ids sur schema_targets"
git push
```

### Task A2 : Migration `excluded_field_ids` sur `schema_block_targets`

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_excluded_field_ids_to_schema_block_targets.rb`

- [ ] **Step 1: Générer + éditer**

```ruby
class AddExcludedFieldIdsToSchemaBlockTargets < ActiveRecord::Migration[7.2]
  def change
    add_column :schema_block_targets, :excluded_field_ids, :jsonb, default: [], null: false
  end
end
```

- [ ] **Step 2: Migrer + Commit**

```bash
bin/rails db:migrate RAILS_ENV=development RAILS_ENV=test
git add db/
git commit -m "feat(refonte): excluded_field_ids sur schema_block_targets"
git push
```

### Task A3 : Helpers d'exclusion sur les modèles + specs

**Files:**
- Modify: `app/models/schema_target.rb`
- Modify: `app/models/schema_block_target.rb`
- Modify: `spec/models/schema_target_spec.rb`
- Modify: `spec/models/schema_block_target_spec.rb`

- [ ] **Step 1: Specs failing**

Ajouter dans `spec/models/schema_target_spec.rb` :

```ruby
describe '#exclude_field!' do
  let(:target) { create(:schema_target, demarche: demarche, excluded_field_ids: []) }

  it 'ajoute un field_id à excluded_field_ids' do
    target.exclude_field!('champ_xyz')
    expect(target.reload.excluded_field_ids).to eq(['champ_xyz'])
  end

  it 'idempotent (ajouter deux fois ne duplique pas)' do
    target.exclude_field!('champ_xyz')
    target.exclude_field!('champ_xyz')
    expect(target.reload.excluded_field_ids).to eq(['champ_xyz'])
  end
end

describe '#include_field!' do
  let(:target) { create(:schema_target, demarche: demarche, excluded_field_ids: ['a', 'b']) }

  it 'retire un field_id' do
    target.include_field!('a')
    expect(target.reload.excluded_field_ids).to eq(['b'])
  end

  it 'idempotent si déjà absent' do
    expect { target.include_field!('zzz') }.not_to(change { target.reload.excluded_field_ids })
  end
end

describe '#field_excluded?' do
  it 'true si dans la liste' do
    target = build(:schema_target, excluded_field_ids: ['x'])
    expect(target.field_excluded?('x')).to be true
  end

  it 'false sinon' do
    target = build(:schema_target, excluded_field_ids: ['x'])
    expect(target.field_excluded?('y')).to be false
  end
end

describe '#exclude_block!, #include_block!, #block_excluded?' do
  let(:target) { create(:schema_target, demarche: demarche) }

  it 'exclut un bloc entier' do
    target.exclude_block!('bloc_a')
    expect(target.reload.block_excluded?('bloc_a')).to be true
  end

  it 'réintègre un bloc' do
    target.exclude_block!('bloc_a')
    target.include_block!('bloc_a')
    expect(target.reload.block_excluded?('bloc_a')).to be false
  end
end
```

Idem dans `spec/models/schema_block_target_spec.rb` pour `exclude_field!` / `include_field!` / `field_excluded?` (mêmes 3 helpers que SchemaTarget).

- [ ] **Step 2: Lancer FAIL**

```bash
bundle exec rspec spec/models/schema_target_spec.rb spec/models/schema_block_target_spec.rb
```

- [ ] **Step 3: Implémenter sur SchemaTarget**

```ruby
# app/models/schema_target.rb — ajouter au modèle existant

def field_excluded?(field_id)
  excluded_field_ids.include?(field_id.to_s)
end

def exclude_field!(field_id)
  return if field_excluded?(field_id)

  update!(excluded_field_ids: excluded_field_ids + [field_id.to_s])
end

def include_field!(field_id)
  return unless field_excluded?(field_id)

  update!(excluded_field_ids: excluded_field_ids - [field_id.to_s])
end

def block_excluded?(block_id)
  excluded_block_descriptor_ids.include?(block_id.to_s)
end

def exclude_block!(block_id)
  return if block_excluded?(block_id)

  update!(excluded_block_descriptor_ids: excluded_block_descriptor_ids + [block_id.to_s])
end

def include_block!(block_id)
  return unless block_excluded?(block_id)

  update!(excluded_block_descriptor_ids: excluded_block_descriptor_ids - [block_id.to_s])
end
```

Sur `SchemaBlockTarget` : seulement les 3 helpers de champ (`field_excluded?`, `exclude_field!`, `include_field!`), pas de notion de bloc imbriqué.

- [ ] **Step 4: PASS + Commit**

```bash
bundle exec rspec spec/models/
bundle exec rubocop -A
git add app/models/ spec/
git commit -m "feat(refonte): helpers d'exclusion sur SchemaTarget et SchemaBlockTarget"
git push
```

---

## Phase B — Differ service (2-3 jours)

### Task B1 : `SchemaBuilders::Differ` — squelette + diff main_table

**Files:**
- Create: `app/lib/schema_builders/differ.rb`
- Create: `spec/lib/schema_builders/differ_spec.rb`

L'API du Differ :

```ruby
differ = SchemaBuilders::Differ.new(target: schema_target, adapter: SchemaBuilders::BaserowTarget.new, demarche_descriptor: descriptor)
diff = differ.main_table_diff
# => {
#   to_add:     [{ id:, label:, type: }, ...],
#   to_modify:  [{ id:, label:, type:, divergence: ... }, ...],
#   ok:         [{ id:, label:, type: }, ...],
#   excluded:   [{ id:, label:, type: }, ...]
# }
```

- [ ] **Step 1: Spec failing**

```ruby
# spec/lib/schema_builders/differ_spec.rb
require 'rails_helper'

RSpec.describe SchemaBuilders::Differ do
  let(:demarche) { create(:demarche) }
  let(:schema_target) { create(:schema_target, demarche: demarche, target_type: 'baserow', main_table_external_id: '101', excluded_field_ids: ['exclu_id']) }
  let(:adapter) { instance_double(SchemaBuilders::BaserowTarget) }

  let(:champ_a) { OpenStruct.new(id: 'a', label: 'Adresse', __typename: 'TextChampDescriptor') }
  let(:champ_b) { OpenStruct.new(id: 'b', label: 'Statut', __typename: 'DropDownListChampDescriptor', options: %w[Oui Non]) }
  let(:champ_c) { OpenStruct.new(id: 'c', label: 'Email', __typename: 'EmailChampDescriptor') }
  let(:champ_excluded) { OpenStruct.new(id: 'exclu_id', label: 'Notes', __typename: 'TextChampDescriptor') }

  let(:demarche_descriptor) do
    OpenStruct.new(champ_descriptors: [champ_a, champ_b, champ_c, champ_excluded])
  end

  let(:differ) { described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: demarche_descriptor) }

  describe '#main_table_diff' do
    context 'avec une table cible existante' do
      before do
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
          { 'name' => 'Adresse', 'type' => 'text' },                               # champ_a → ok
          { 'name' => 'Statut', 'type' => 'text' }                                  # champ_b → to_modify (type divergent)
          # champ_c manque → to_add
        ])
      end

      it 'classe le champ conforme dans ok' do
        diff = differ.main_table_diff
        expect(diff[:ok].map { |f| f[:id] }).to include('a')
      end

      it 'classe le champ manquant dans to_add' do
        diff = differ.main_table_diff
        expect(diff[:to_add].map { |f| f[:id] }).to include('c')
      end

      it 'classe le champ avec type divergent dans to_modify' do
        diff = differ.main_table_diff
        expect(diff[:to_modify].map { |f| f[:id] }).to include('b')
      end

      it 'classe les champs exclus dans excluded même s\'ils manqueraient' do
        diff = differ.main_table_diff
        expect(diff[:excluded].map { |f| f[:id] }).to eq(['exclu_id'])
        expect(diff[:to_add].map { |f| f[:id] }).not_to include('exclu_id')
      end
    end

    context 'avec une table inexistante (premier Build)' do
      before do
        schema_target.update!(main_table_external_id: nil)
      end

      it 'classe tout en to_add (sauf exclus)' do
        diff = differ.main_table_diff
        expect(diff[:to_add].map { |f| f[:id] }).to contain_exactly('a', 'b', 'c')
        expect(diff[:excluded].map { |f| f[:id] }).to eq(['exclu_id'])
      end

      it 'ne fait pas d\'appel à adapter.get_table_fields' do
        expect(adapter).not_to receive(:get_table_fields)
        differ.main_table_diff
      end
    end
  end
end
```

- [ ] **Step 2: Lancer FAIL**

- [ ] **Step 3: Implémenter**

```ruby
# app/lib/schema_builders/differ.rb
module SchemaBuilders
  class Differ
    def initialize(target:, adapter:, demarche_descriptor:)
      @target = target
      @adapter = adapter
      @demarche_descriptor = demarche_descriptor
    end

    def main_table_diff
      md_fields = filterable_main_fields
      target_fields = main_table_existing_fields

      classify(md_fields, target_fields, excluded_predicate: ->(f) { @target.field_excluded?(f[:id]) })
    end

    private

    def filterable_main_fields
      @demarche_descriptor.champ_descriptors
        .reject { |c| c.__typename == 'RepetitionChampDescriptor' }
        .map { |c| descriptor_to_field(c) }
    end

    def main_table_existing_fields
      return [] if @target.main_table_external_id.blank?

      @adapter.get_table_fields(@target.main_table_external_id)
        .map { |f| { name: f['name'] || f[:name], type: f['type'] || f[:type] } }
    rescue StandardError => e
      Rails.logger.warn "Differ: unable to fetch target fields: #{e.message}"
      []
    end

    def classify(md_fields, target_fields, excluded_predicate:)
      result = { to_add: [], to_modify: [], ok: [], excluded: [] }
      target_by_name = target_fields.index_by { |f| f[:name] }

      md_fields.each do |field|
        if excluded_predicate.call(field)
          result[:excluded] << field
        elsif (existing = target_by_name[field[:label]])
          if compatible?(field, existing)
            result[:ok] << field
          else
            result[:to_modify] << field.merge(divergence: divergence_label(field, existing))
          end
        else
          result[:to_add] << field
        end
      end

      result
    end

    def descriptor_to_field(champ)
      {
        id: champ.id,
        label: champ.label,
        type: simple_type_for(champ),
        options: champ.respond_to?(:options) ? champ.options : nil
      }
    end

    def simple_type_for(champ)
      champ.__typename.sub('ChampDescriptor', '').gsub(/(.)([A-Z])/, '\1_\2').downcase
    end

    def compatible?(md_field, target_field)
      # Comparaison simple : pour l'instant on considère ok si les noms matchent.
      # Le type est mappé par le TypeMapper, donc on ne peut pas comparer 1-1 ici
      # sans embarquer la logique de mapping. Pour les options de dropdown,
      # une comparaison set est suffisante.
      # Décision pragmatique : retourner true si nom OK, et flagger en divergence
      # uniquement si on détecte un type radicalement différent (text vs number par ex).
      md_simple = md_field[:type]
      tgt = target_field[:type].to_s
      # Heuristique : si l'un est numeric et l'autre text, c'est divergent
      return false if numeric?(md_simple) != numeric?(tgt)

      true
    end

    def numeric?(type)
      type.to_s.match?(/integer|decimal|number|float/)
    end

    def divergence_label(md_field, target_field)
      "Type cible '#{target_field[:type]}' ne correspond pas à '#{md_field[:type]}'"
    end
  end
end
```

**Note** : la comparaison « compatibles » est volontairement laxiste pour cette première itération. Si l'utilisateur trouve qu'on flag trop souvent ou pas assez, on raffine. C'est un raffinement à ajuster en QA.

- [ ] **Step 4: PASS + Commit**

```bash
bundle exec rubocop -A
git add app/lib/schema_builders/differ.rb spec/
git commit -m "feat(refonte): SchemaBuilders::Differ#main_table_diff (4 collections)"
git push
```

### Task B2 : `Differ#blocks_diff`

**Files:**
- Modify: `app/lib/schema_builders/differ.rb`
- Modify: `spec/lib/schema_builders/differ_spec.rb`

L'API :

```ruby
diff = differ.blocks_diff
# => {
#   blocks_excluded: [{ id:, label: }, ...],  # blocs entiers ignorés
#   blocks: [
#     {
#       id: 'b1',
#       label: 'Membres',
#       excluded: false,
#       schema_block_target: <SchemaBlockTarget>,  # auto-créé
#       diff: { to_add: [...], to_modify: [...], ok: [...], excluded: [...] }
#     },
#     { id: 'b2', label: 'Activités', excluded: true, schema_block_target: nil, diff: nil }
#   ]
# }
```

L'autocréation de `SchemaBlockTarget` : si un bloc n'est pas exclus, on cherche son `SchemaBlockTarget`, sinon on le crée avec `backend_table_id: nil`.

- [ ] **Step 1: Spec** : couvrir un cas avec 3 blocs (1 exclus, 1 nouveau, 1 existant avec champs à modifier).

- [ ] **Step 2: Implémenter**

```ruby
def blocks_diff
  blocks = @demarche_descriptor.champ_descriptors.select { |c| c.__typename == 'RepetitionChampDescriptor' }
  excluded, included = blocks.partition { |b| @target.block_excluded?(b.id) }

  {
    blocks_excluded: excluded.map { |b| { id: b.id, label: b.label } },
    blocks: included.map { |b| block_entry(b) }
  }
end

private

def block_entry(block)
  block_target = ensure_block_target(block)
  block_target_external = block_target.backend_table_id
  inner_md_fields = block.champ_descriptors.map { |c| descriptor_to_field(c) }
  inner_target_fields = block_target_external.present? ? @adapter.get_table_fields(block_target_external).map { |f| { name: f['name'] || f[:name], type: f['type'] || f[:type] } } : []

  inner_diff = classify(inner_md_fields, inner_target_fields, excluded_predicate: ->(f) { block_target.field_excluded?(f[:id]) })

  {
    id: block.id,
    label: block.label,
    excluded: false,
    schema_block_target: block_target,
    diff: inner_diff
  }
end

def ensure_block_target(block)
  @target.schema_block_targets.find_or_create_by!(block_descriptor_id: block.id)
end
```

- [ ] **Step 3: PASS + Commit**

```bash
git add app/lib/schema_builders/differ.rb spec/
git commit -m "feat(refonte): SchemaBuilders::Differ#blocks_diff avec auto-création de SchemaBlockTarget"
git push
```

---

## Phase C — Endpoints + controller (2 jours)

### Task C1 : Endpoint PATCH exclusion champ table principale

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/admin/schema_builder_controller.rb`
- Modify: `spec/controllers/admin/schema_builder_controller_spec.rb`

Route :

```ruby
patch 'targets/:target/main_table/fields/:field_id/exclusion',
      to: 'schema_builder#toggle_main_table_field_exclusion',
      as: :toggle_main_table_field_exclusion
```

Controller action :

```ruby
def toggle_main_table_field_exclusion
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  excluded = ActiveModel::Type::Boolean.new.cast(params[:excluded])
  if excluded
    target.exclude_field!(params[:field_id])
  else
    target.include_field!(params[:field_id])
  end

  diff = differ_for(target).main_table_diff

  render turbo_stream: turbo_stream.replace(
    "main-table-#{target.id}",
    partial: 'main_table_section',
    locals: { target: target, diff: diff }
  )
end

private

def differ_for(target)
  SchemaBuilders::Differ.new(
    target: target,
    adapter: target_adapter_for(target),
    demarche_descriptor: demarche_descriptor
  )
end
```

Spec : test que PATCH avec `excluded=true` ajoute le field, `excluded=false` le retire, et la réponse Turbo Stream contient la section re-rendue.

Commit : `feat(refonte): endpoint toggle exclusion champ table principale`

### Task C2 : Endpoints PATCH exclusion bloc entier + champ dans bloc

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/admin/schema_builder_controller.rb`
- Modify: `spec/controllers/admin/schema_builder_controller_spec.rb`

Routes :

```ruby
patch 'targets/:target/blocks/:block_id/exclusion',
      to: 'schema_builder#toggle_block_exclusion',
      as: :toggle_block_exclusion
patch 'targets/:target/blocks/:block_id/fields/:field_id/exclusion',
      to: 'schema_builder#toggle_block_field_exclusion',
      as: :toggle_block_field_exclusion
```

Controller :

```ruby
def toggle_block_exclusion
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  excluded = ActiveModel::Type::Boolean.new.cast(params[:excluded])
  if excluded
    target.exclude_block!(params[:block_id])
  else
    target.include_block!(params[:block_id])
  end

  diff = differ_for(target).blocks_diff
  render turbo_stream: turbo_stream.replace(
    "blocks-#{target.id}",
    partial: 'blocks_section',
    locals: { target: target, diff: diff }
  )
end

def toggle_block_field_exclusion
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  block_target = target.schema_block_targets.find_by!(block_descriptor_id: params[:block_id])
  excluded = ActiveModel::Type::Boolean.new.cast(params[:excluded])
  if excluded
    block_target.exclude_field!(params[:field_id])
  else
    block_target.include_field!(params[:field_id])
  end

  diff = differ_for(target).blocks_diff
  render turbo_stream: turbo_stream.replace(
    "blocks-#{target.id}",
    partial: 'blocks_section',
    locals: { target: target, diff: diff }
  )
end
```

Specs idem C1 mais pour les 2 endpoints.

Commit : `feat(refonte): endpoints toggle exclusion bloc et champ-dans-bloc`

### Task C3 : Actions `preview_main_table` + `preview_blocks` revues pour utiliser le Differ

**Files:**
- Modify: `app/controllers/admin/schema_builder_controller.rb`
- Modify: `spec/controllers/admin/schema_builder_controller_spec.rb`

`preview_main_table` retourne désormais le diff au lieu de la simple liste :

```ruby
def preview_main_table
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  diff = differ_for(target).main_table_diff

  render turbo_stream: turbo_stream.replace(
    "main-table-#{target.id}",
    partial: 'main_table_section',
    locals: { target: target, diff: diff }
  )
end
```

Idem pour `preview_blocks` qui retourne `blocks_diff`.

Spec : mettre à jour pour pointer les nouvelles structures.

Commit : `refactor(refonte): preview actions utilisent SchemaBuilders::Differ`

### Task C4 : Actions `build_main_table` + `build_blocks` respectent les exclusions

**Files:**
- Modify: `app/controllers/admin/schema_builder_controller.rb`
- Modify: `app/lib/schema_builders/main_table_builder.rb` (ajout d'un param `excluded_field_ids`)
- Modify: `app/lib/schema_builders/block_builder.rb` (idem + skip blocs exclus)
- Modify: `spec/lib/schema_builders/` + `spec/controllers/`

Modifier `MainTableBuilder#build!` :

```ruby
def build!(demarche_descriptor, application_id:, table_name:, excluded_field_ids: [])
  fields = build_fields(demarche_descriptor).reject { |f| excluded_field_ids.include?(f[:id].to_s) }
  # ... reste inchangé
end
```

Modifier `BlockBuilder#build!` pour accepter `excluded_block_ids:` et `excluded_fields_per_block:` :

```ruby
def build!(demarche_descriptor, application_id:, main_table_id:, excluded_block_ids: [], excluded_fields_per_block: {})
  blocks_from(demarche_descriptor).reject { |b| excluded_block_ids.include?(b.id) }.map do |block|
    excluded_inner = excluded_fields_per_block[block.id] || []
    # ... même logique mais filtrage des champs sur excluded_inner
  end
end
```

Mise à jour des actions controller pour passer les exclusions :

```ruby
def build_main_table
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  builder = main_table_builder_for(target)
  result = builder.build!(
    demarche_descriptor,
    application_id: target.application_external_id,
    table_name: main_table_name_for(target),
    excluded_field_ids: target.excluded_field_ids
  )
  # ... reste idem
end

def build_blocks
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  builder = block_builder_for(target)
  excluded_fields_per_block = target.schema_block_targets.each_with_object({}) do |bt, h|
    h[bt.block_descriptor_id] = bt.excluded_field_ids
  end
  results = builder.build!(
    demarche_descriptor,
    application_id: target.application_external_id,
    main_table_id: target.main_table_external_id,
    excluded_block_ids: target.excluded_block_descriptor_ids,
    excluded_fields_per_block: excluded_fields_per_block
  )
  # ... persistance idem
end
```

Mettre à jour les specs des builders + controller.

Commit : `feat(refonte): build actions respectent les exclusions stockées`

---

## Phase D — Vues HAML + Turbo Frame lazy (2-3 jours)

### Task D1 : Vue `_main_table_section` refondue avec diff + checkboxes

**Files:**
- Modify: `app/views/admin/schema_builder/_main_table_section.html.haml`
- Create: `app/views/admin/schema_builder/_field_checkbox.html.haml` (partial réutilisable)

Structure cible :

```haml
%turbo-frame{ id: "main-table-#{target.id}", src: (local_assigns[:diff] ? nil : preview_main_table_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type)), loading: :lazy, data: { turbo_method: :post } }
  - if local_assigns[:diff]
    = render 'main_table_section_loaded', target: target, diff: diff
  - else
    %div.card.mt-3
      %div.card-header
        %h5.mb-0 Table principale
      %div.card-body.text-center.text-muted
        %div.spinner-border.spinner-border-sm.me-2
        Chargement de l'aperçu…
```

Pour le partial chargé `_main_table_section_loaded.html.haml` (rendu serveur après preview) :

```haml
%div.card.mt-3
  %div.card-header.d-flex.justify-content-between.align-items-center
    %h5.mb-0
      Table principale
      %span.badge.bg-secondary.ms-2= main_table_status_label(target)

  %div.card-body
    -# Section À ajouter
    - if diff[:to_add].any?
      %h6.text-success 🟢 À ajouter (#{diff[:to_add].size})
      - diff[:to_add].each do |field|
        = render 'field_checkbox', target: target, field: field, scope: :main_table, checked: true
    -# Section À modifier
    - if diff[:to_modify].any?
      %h6.text-warning.mt-3 🟡 À modifier (#{diff[:to_modify].size})
      - diff[:to_modify].each do |field|
        = render 'field_checkbox', target: target, field: field, scope: :main_table, checked: true, divergence: field[:divergence]
    -# Section OK (collapsé)
    - if diff[:ok].any?
      %details.mt-3
        %summary.text-muted ▶ #{diff[:ok].size} champs conformes (cliquer pour déplier)
        %ul.list-unstyled
          - diff[:ok].each do |field|
            %li.text-muted= "#{field[:label]} (#{field[:type]})"
    -# Section Ignorés
    - if diff[:excluded].any?
      %h6.text-secondary.mt-3 ⛔ Ignorés (#{diff[:excluded].size})
      - diff[:excluded].each do |field|
        = render 'field_checkbox', target: target, field: field, scope: :main_table, checked: false

    -# Bouton Build (compteur dynamique)
    - to_sync_count = diff[:to_add].size + diff[:to_modify].size
    %div.mt-4
      = button_to "Synchroniser #{to_sync_count} champ#{'s' if to_sync_count > 1}", build_main_table_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type), method: :post, class: "btn btn-primary #{'disabled' if to_sync_count.zero?}", data: { turbo_frame: "main-table-#{target.id}", turbo_confirm: 'Synchroniser ?', controller: 'build-action', action: 'click->build-action#start' }, disabled: to_sync_count.zero?
```

Partial `_field_checkbox.html.haml` :

```haml
%div.form-check.d-inline-block.me-3
  = check_box_tag "exclusion_#{field[:id]}", '1', checked, class: 'form-check-input', data: {
    controller: 'exclusion-toggle',
    action: 'change->exclusion-toggle#toggle',
    exclusion_toggle_url_value: toggle_url_for(target, scope, field),
    exclusion_toggle_field_id_value: field[:id]
  }
  %label.form-check-label
    = field[:label]
    %code.ms-2= field[:type]
    - if local_assigns[:divergence]
      %small.text-muted.ms-2= "(#{divergence})"
```

Définir `toggle_url_for` dans le helper :

```ruby
# app/helpers/schema_builder_helper.rb
def toggle_url_for(target, scope, field)
  case scope
  when :main_table
    toggle_main_table_field_exclusion_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type, field_id: field[:id])
  when :block_field
    toggle_block_field_exclusion_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type, block_id: field[:block_id], field_id: field[:id])
  end
end
```

Commit : `feat(refonte): vue _main_table_section diff-only avec checkboxes`

### Task D2 : Stimulus `exclusion_toggle_controller`

**Files:**
- Create: `app/javascript/controllers/exclusion_toggle_controller.js`

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, fieldId: String }

  async toggle(event) {
    const excluded = !event.target.checked
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
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
      Turbo.renderStreamMessage(streamHtml)
    }
  }
}
```

Note importante : la response Turbo Stream remplace la section complète, ce qui invalide les checkboxes existantes (elles disparaissent puisque le DOM est remplacé). Pas besoin de mettre à jour l'état localement.

Commit : `feat(refonte): Stimulus exclusion_toggle controller`

### Task D3 : Vue `_blocks_section` refondue à 2 niveaux

**Files:**
- Modify: `app/views/admin/schema_builder/_blocks_section.html.haml`

```haml
%turbo-frame{ id: "blocks-#{target.id}", src: (local_assigns[:diff] ? nil : preview_blocks_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type)), loading: :lazy, data: { turbo_method: :post } }
  - if local_assigns[:diff]
    %div.card.mt-3
      %div.card-header
        %h5.mb-0 Blocs répétables
      %div.card-body
        -# Blocs visibles avec leur diff interne
        - diff[:blocks].each do |entry|
          %div.mb-4
            %div.form-check
              = check_box_tag "block_excl_#{entry[:id]}", '1', true, class: 'form-check-input', data: {
                controller: 'exclusion-toggle',
                action: 'change->exclusion-toggle#toggle',
                exclusion_toggle_url_value: toggle_block_exclusion_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type, block_id: entry[:id])
              }
              %label.form-check-label
                %strong= entry[:label]

            %div.ms-4
              - inner = entry[:diff]
              - if inner[:to_add].any?
                %div.mt-2
                  %strong.text-success 🟢 À ajouter (#{inner[:to_add].size})
                  - inner[:to_add].each do |field|
                    = render 'block_field_checkbox', target: target, block_id: entry[:id], field: field, checked: true
              - if inner[:to_modify].any?
                %div.mt-2
                  %strong.text-warning 🟡 À modifier (#{inner[:to_modify].size})
                  - inner[:to_modify].each do |field|
                    = render 'block_field_checkbox', target: target, block_id: entry[:id], field: field, checked: true
              - if inner[:ok].any?
                %details.mt-2
                  %summary.text-muted ▶ #{inner[:ok].size} champs conformes
                  %ul.list-unstyled
                    - inner[:ok].each do |field|
                      %li.text-muted= "#{field[:label]} (#{field[:type]})"
              - if inner[:excluded].any?
                %div.mt-2
                  %strong.text-secondary ⛔ Ignorés (#{inner[:excluded].size})
                  - inner[:excluded].each do |field|
                    = render 'block_field_checkbox', target: target, block_id: entry[:id], field: field, checked: false

        -# Blocs entiers exclus (cachés sauf un titre rappel + checkbox)
        - diff[:blocks_excluded].each do |b|
          %div.mb-2
            %div.form-check
              = check_box_tag "block_excl_#{b[:id]}", '1', false, class: 'form-check-input', data: {
                controller: 'exclusion-toggle',
                action: 'change->exclusion-toggle#toggle',
                exclusion_toggle_url_value: toggle_block_exclusion_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type, block_id: b[:id])
              }
              %label.form-check-label.text-muted= b[:label]

        -# Bouton Build global
        - total_to_sync = diff[:blocks].sum { |b| b[:diff][:to_add].size + b[:diff][:to_modify].size }
        %div.mt-4
          = button_to "Synchroniser les blocs (#{total_to_sync} champs)", build_blocks_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type), method: :post, class: "btn btn-primary #{'disabled' if total_to_sync.zero?}", data: { turbo_frame: "blocks-#{target.id}", turbo_confirm: 'Synchroniser ?', controller: 'build-action', action: 'click->build-action#start' }, disabled: total_to_sync.zero?
  - else
    %div.card.mt-3
      %div.card-header
        %h5.mb-0 Blocs répétables
      %div.card-body.text-center.text-muted
        %div.spinner-border.spinner-border-sm.me-2
        Chargement…
```

Et créer `_block_field_checkbox.html.haml` :

```haml
%div.form-check.d-inline-block.me-3
  = check_box_tag "block_#{block_id}_field_#{field[:id]}", '1', checked, class: 'form-check-input', data: {
    controller: 'exclusion-toggle',
    action: 'change->exclusion-toggle#toggle',
    exclusion_toggle_url_value: toggle_block_field_exclusion_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type, block_id: block_id, field_id: field[:id])
  }
  %label.form-check-label
    = field[:label]
    %code.ms-2= field[:type]
```

Commit : `feat(refonte): vue _blocks_section diff-only à 2 niveaux d'exclusion`

### Task D4 : Vue `_avis_section` — lazy load preview seul

**Files:**
- Modify: `app/views/admin/schema_builder/_avis_section.html.haml`

L'avis a un schéma fixe, pas de notion de diff. On garde le bouton Build, mais on convertit en Turbo Frame lazy pour cohérence visuelle (status display au load).

```haml
%turbo-frame{ id: "avis-#{target.id}" }
  %div.card.mt-3
    %div.card-header
      %h5.mb-0
        Table Avis
        %span.badge.bg-secondary.ms-2= avis_status_label(target)
    %div.card-body
      - if target.target_type == 'grist'
        %p.text-muted.mb-0 Fonctionnalité indisponible pour Grist
      - elsif target.main_table_external_id.blank?
        %p.text-muted.mb-0 La table principale doit être créée avant la table Avis.
      - else
        = button_to 'Build Avis', build_avis_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type), method: :post, class: 'btn btn-primary', data: { turbo_frame: "avis-#{target.id}", turbo_confirm: 'Créer/maj la table Avis ?', controller: 'build-action', action: 'click->build-action#start' }
        - if local_assigns[:preview]
          = render 'preview_result', preview: preview
        - if local_assigns[:build_result]
          = render 'build_result', build_result: build_result
```

Le bouton Aperçu est retiré (pas de notion de diff). Si l'utilisateur veut voir le schéma, il clique Build directement (idempotent grâce à `update_fields`).

Commit : `refactor(refonte): _avis_section simplifié (pas de diff, juste Build)`

### Task D5 : `show.html.haml` et `_target_panel` adaptés

**Files:**
- Verify: `app/views/admin/schema_builder/_target_panel.html.haml`
- Verify: `app/views/admin/schema_builder/show.html.haml`

Vérifier que les `= render` partials sont compatibles avec le nouveau pattern Turbo Frame lazy. Pas d'autre changement attendu.

Commit minimal si rien à modifier — on saute si vraiment rien.

---

## Phase E — Specs d'intégration (1 jour)

### Task E1 : System-ish request spec end-to-end

**Files:**
- Modify: `spec/requests/admin/schema_builder_spec.rb`

Ajouter un scénario complet :

1. Créer une démarche + SchemaTarget Baserow + main_table_external_id
2. Stubber l'adapter pour retourner 3 champs MD et 2 champs côté target (1 commun, 1 manquant côté target = "à ajouter")
3. GET le dashboard → vérifier que la section main_table contient le Turbo Frame lazy avec src
4. POST preview → vérifier que la response contient bien "À ajouter" et le champ attendu
5. PATCH toggle exclusion du champ "à ajouter" → vérifier qu'il bascule dans "Ignorés"
6. POST build → vérifier que SEUL le non-exclus est synchronisé

Commit : `test(refonte): spec end-to-end du flow diff + exclusion + build`

---

## Checkpoint final de l'extension

Avant de considérer ce chantier terminé :

- [ ] Toute la suite passe : `bundle exec rspec`
- [ ] Lint clean : `bundle exec rake lint`
- [ ] Le dashboard charge les sections en lazy (Turbo Frame)
- [ ] Le diff affiche les 4 zones correctement
- [ ] Les checkboxes togglent l'exclusion et la persistance survit au reload
- [ ] Build respecte les exclusions
- [ ] Bloc entier exclus → contenu caché, juste un titre + checkbox
- [ ] Compteur dynamique sur le bouton Build
- [ ] QA manuelle effectuée sur staging avec une démarche réelle

À l'issue : PR ouverte de `feature/ui-refonte` vers `dev`, code review, merge.
