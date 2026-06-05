# Refonte UI — Slice 1 (Builder Schema) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refondre le builder Baserow/Grist en un dashboard itératif scopé à la démarche, avec persistance (cibles mémorisées), Hotwire (Turbo + Stimulus), et abstraction backend pragmatique consolidant les deux namespaces parallèles existants.

**Architecture:** Nouveau namespace `SchemaBuilders` (Target + Builders agnostiques de la cible), nouveau controller unique `Admin::SchemaBuilderController` scopé démarche, nouveaux modèles `SchemaTarget` + `SchemaBlockTarget`, vues HAML avec Turbo Frames/Streams (pas de JS inline), Stimulus controllers JS pour la cascade et le pli/dépli. Backward compat via page legacy intermédiaire. Migration de données via rake task idempotent.

**Tech Stack:** Rails 7.2.3, Ruby 3.4.4, Hotwire (Turbo 8 + Stimulus 3), import maps (`importmap-rails`), Bootstrap 5 (conservé), HAML, RSpec + FactoryBot, Capybara + Cuprite (système).

**Branche:** `feature/ui-refonte` (déjà créée, partie de `dev`).

**Spec source:** `docs/superpowers/specs/2026-05-28-ui-refonte-design.md`.

---

## Conventions de ce plan

- **Avant chaque commit code Ruby/SCSS** : exécuter `bundle exec rubocop -A` puis `bundle exec rake lint` (règle CLAUDE.md). Pour les commits purement `.md`, ignorer.
- **TDD discipliné** : Red → Green → Commit. Pas de refacto sans test couvrant.
- **Commits atomiques** : un commit par tâche complétée. Messages en français, format Conventional Commits (`feat:`, `refactor:`, `test:`, `docs:`, `chore:`).
- **Push** au fil de l'eau (autonomie autorisée pour ce chantier).
- **Push interdit sur `master`** — toujours via `dev` (cf. workflow projet).

---

## Phase A — Foundation Hotwire (1-2 jours)

Installer Turbo + Stimulus + import maps. Garder Sprockets en parallèle pour ne rien casser sur les pages existantes. La cohabitation jQuery/Turbolinks + Hotwire reste valide jusqu'au Slice 3.

### Task A1 : Ajouter les gems Hotwire

**Files:**
- Modify: `Gemfile`
- Modify: `Gemfile.lock` (auto)

- [ ] **Step 1: Éditer le Gemfile**

Ajouter (après `gem 'cssbundling-rails'`) :

```ruby
gem 'turbo-rails', '~> 2.0'
gem 'stimulus-rails', '~> 1.3'
gem 'importmap-rails', '~> 2.0'
```

Note: ne PAS retirer `turbolinks`, `jquery-rails`, `coffee-rails`, `sprockets-rails` à ce stade (cleanup en Slice 3).

- [ ] **Step 2: Installer**

```bash
bundle install
```

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "feat(refonte): ajout gems Hotwire (turbo-rails, stimulus-rails, importmap-rails)"
git push
```

### Task A2 : Initialiser import maps + Stimulus + Turbo

**Files:**
- Create: `config/importmap.rb`
- Create: `app/javascript/application.js`
- Create: `app/javascript/controllers/index.js`
- Create: `app/javascript/controllers/application.js`
- Modify: `app/views/layouts/application.html.haml`
- Modify: `config/application.rb` (éventuellement, pour autoload)

- [ ] **Step 1: Générer import maps via rails command**

```bash
bin/rails importmap:install
```

Cette commande crée `config/importmap.rb`, `app/javascript/application.js`, et insère `<%= javascript_importmap_tags %>` dans le layout. Si le layout est en HAML, l'insertion automatique peut échouer — on l'ajoute manuellement à l'étape 4.

- [ ] **Step 2: Générer Turbo**

```bash
bin/rails turbo:install
```

Si la commande tente de remplacer Turbolinks dans `application.js` style Sprockets, accepter mais vérifier qu'on ne casse pas l'ancien JS pour l'instant — Turbolinks doit RESTER actif pendant le Slice 1. On garde donc l'import de turbolinks dans `app/assets/javascripts/application.js` (manifest Sprockets) et on ajoute Turbo via les import maps.

- [ ] **Step 3: Générer Stimulus**

```bash
bin/rails stimulus:install
```

Cela crée `app/javascript/controllers/application.js` et `app/javascript/controllers/index.js`.

- [ ] **Step 4: Vérifier le layout HAML**

Lire `app/views/layouts/application.html.haml`. S'assurer que dans le `%head`, on a les deux types de tags :

```haml
= stylesheet_link_tag 'application', media: 'all'
= javascript_include_tag 'application'  -# ancien Sprockets, à conserver
= javascript_importmap_tags             -# nouveau Hotwire
```

Si `javascript_importmap_tags` manque, l'ajouter manuellement après `javascript_include_tag`.

- [ ] **Step 5: Vérifier en lançant le serveur**

```bash
bin/rails server
```

Dans une autre session :

```bash
curl -s http://localhost:3000/ 2>&1 | grep -E "importmap|turbo|stimulus" | head -10
```

Attendu : références à `@hotwired/turbo`, `@hotwired/stimulus`, et `controllers/application` dans le HTML.

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add -A
git commit -m "feat(refonte): installation Hotwire (Turbo + Stimulus + import maps)"
git push
```

### Task A3 : Smoke test — Stimulus hello controller

**Files:**
- Create: `app/javascript/controllers/hello_controller.js`
- Create: `spec/system/hotwire_smoke_spec.rb`
- Modify: `spec/rails_helper.rb` (config Capybara/Cuprite si absente)

- [ ] **Step 1: Vérifier la présence de Capybara + driver**

```bash
grep -E "capybara|cuprite|selenium" Gemfile
```

Si absent :

```ruby
# Gemfile (group :test do)
gem 'capybara', '~> 3.40'
gem 'cuprite', '~> 0.15'
```

Puis :

```bash
bundle install
git add Gemfile Gemfile.lock
git commit -m "test(refonte): ajout Capybara + Cuprite pour specs système"
```

- [ ] **Step 2: Configurer Capybara + Cuprite dans rails_helper**

Créer `spec/support/system_test_config.rb` :

```ruby
require 'capybara/cuprite'

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1280, 800], headless: true)
end

Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :rack_test
  end
  config.before(:each, type: :system, js: true) do
    driven_by :cuprite
  end
end
```

Vérifier que `spec/rails_helper.rb` charge `spec/support/**/*.rb` (typiquement déjà le cas via `Dir[Rails.root.join('spec/support/**/*.rb')].each { |f| require f }`).

- [ ] **Step 3: Écrire le hello controller Stimulus**

```javascript
// app/javascript/controllers/hello_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output"]

  connect() {
    this.outputTarget.textContent = "Hotwire opérationnel"
  }
}
```

- [ ] **Step 4: Écrire le failing test**

```ruby
# spec/system/hotwire_smoke_spec.rb
require 'rails_helper'

RSpec.describe 'Hotwire smoke', type: :system, js: true do
  it 'le Stimulus hello controller boote' do
    # On crée une route éphémère via une vue test, ou on injecte
    # un fragment dans une page existante. Le plus simple :
    visit '/__hotwire_smoke'
    expect(page).to have_text('Hotwire opérationnel')
  end
end
```

- [ ] **Step 5: Ajouter route + vue de smoke (transitoire, supprimée en Phase K)**

```ruby
# config/routes.rb — ajouter avant la route racine
get '/__hotwire_smoke', to: 'smoke#hotwire' if Rails.env.development? || Rails.env.test?
```

```ruby
# app/controllers/smoke_controller.rb
class SmokeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:hotwire]

  def hotwire
    render inline: <<~HAML, type: :haml, layout: 'application'
      %div{data: { controller: 'hello' }}
        %span{data: { hello_target: 'output' }} placeholder
    HAML
  end
end
```

- [ ] **Step 6: Lancer le test, attendre PASS**

```bash
bundle exec rspec spec/system/hotwire_smoke_spec.rb
```

Si échec : vérifier console navigateur via Cuprite (`page.driver.browser.command('Browser.getVersion')` ou logs).

- [ ] **Step 7: Commit**

```bash
bundle exec rubocop -A
git add -A
git commit -m "test(refonte): smoke test Hotwire (Stimulus hello controller)"
git push
```

---

## Phase B — Data layer (1 jour)

Migrations et modèles `SchemaTarget` + `SchemaBlockTarget`. Pas d'UI encore.

### Task B1 : Migration `schema_targets`

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_schema_targets.rb`

- [ ] **Step 1: Générer la migration**

```bash
bin/rails generate migration CreateSchemaTargets demarche:references target_type:string workspace_external_id:string application_external_id:string main_table_external_id:string avis_table_external_id:string last_synced_at:datetime
```

- [ ] **Step 2: Éditer la migration générée**

```ruby
class CreateSchemaTargets < ActiveRecord::Migration[7.2]
  def change
    create_table :schema_targets do |t|
      t.references :demarche, null: false, foreign_key: true
      t.string :target_type, null: false
      t.string :workspace_external_id
      t.string :application_external_id
      t.string :main_table_external_id
      t.string :avis_table_external_id
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :schema_targets, [:demarche_id, :target_type], unique: true
  end
end
```

- [ ] **Step 3: Migrer**

```bash
bin/rails db:migrate RAILS_ENV=development
bin/rails db:migrate RAILS_ENV=test
```

- [ ] **Step 4: Commit**

```bash
git add db/
git commit -m "feat(refonte): migration schema_targets"
git push
```

### Task B2 : Migration `schema_block_targets`

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_schema_block_targets.rb`

- [ ] **Step 1: Générer**

```bash
bin/rails generate migration CreateSchemaBlockTargets schema_target:references block_descriptor_id:string backend_table_id:string last_synced_at:datetime
```

- [ ] **Step 2: Éditer**

```ruby
class CreateSchemaBlockTargets < ActiveRecord::Migration[7.2]
  def change
    create_table :schema_block_targets do |t|
      t.references :schema_target, null: false, foreign_key: true
      t.string :block_descriptor_id, null: false
      t.string :backend_table_id
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :schema_block_targets, [:schema_target_id, :block_descriptor_id], unique: true, name: 'idx_schema_block_targets_unique'
  end
end
```

- [ ] **Step 3: Migrer**

```bash
bin/rails db:migrate RAILS_ENV=development
bin/rails db:migrate RAILS_ENV=test
```

- [ ] **Step 4: Commit**

```bash
git add db/
git commit -m "feat(refonte): migration schema_block_targets"
git push
```

### Task B3 : Modèle `SchemaTarget` + spec

**Files:**
- Create: `app/models/schema_target.rb`
- Create: `spec/models/schema_target_spec.rb`
- Create: `spec/factories/schema_targets.rb`

- [ ] **Step 1: Écrire le spec failing**

```ruby
# spec/models/schema_target_spec.rb
require 'rails_helper'

RSpec.describe SchemaTarget, type: :model do
  describe 'validations' do
    let(:demarche) { create(:demarche) }
    let(:valid_attrs) { { demarche: demarche, target_type: 'baserow' } }

    it 'est valide avec demarche + target_type baserow' do
      expect(SchemaTarget.new(valid_attrs)).to be_valid
    end

    it 'est valide avec target_type grist' do
      expect(SchemaTarget.new(valid_attrs.merge(target_type: 'grist'))).to be_valid
    end

    it 'rejette un target_type inconnu' do
      expect { SchemaTarget.new(valid_attrs.merge(target_type: 'notion')) }
        .to raise_error(ArgumentError, /not a valid target_type/)
    end

    it 'exige demarche' do
      expect(SchemaTarget.new(target_type: 'baserow')).not_to be_valid
    end

    it 'exige target_type' do
      expect(SchemaTarget.new(demarche: demarche)).not_to be_valid
    end

    it 'unicité de (demarche_id, target_type)' do
      SchemaTarget.create!(valid_attrs)
      duplicate = SchemaTarget.new(valid_attrs)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:demarche_id]).to include(/taken/i)
    end

    it 'autorise même démarche avec un target_type différent' do
      SchemaTarget.create!(valid_attrs)
      other = SchemaTarget.new(valid_attrs.merge(target_type: 'grist'))
      expect(other).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs_to demarche' do
      assoc = described_class.reflect_on_association(:demarche)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it 'has_many schema_block_targets dependent destroy' do
      assoc = described_class.reflect_on_association(:schema_block_targets)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end
  end
end
```

- [ ] **Step 2: Créer la factory**

```ruby
# spec/factories/schema_targets.rb
FactoryBot.define do
  factory :schema_target do
    association :demarche
    target_type { 'baserow' }
    workspace_external_id { '42' }
    application_external_id { '17' }
    main_table_external_id { '101' }
  end
end
```

Note : vérifier que `spec/factories/demarches.rb` existe ; sinon créer :

```ruby
# spec/factories/demarches.rb
FactoryBot.define do
  factory :demarche do
    sequence(:configuration) { |n| "config_#{n}" }
    sequence(:libelle) { |n| "Démarche test #{n}" }
    instructeur { 'test@example.com' }
  end
end
```

- [ ] **Step 3: Lancer le spec, attendre FAIL**

```bash
bundle exec rspec spec/models/schema_target_spec.rb
```

Attendu : NameError uninitialized constant SchemaTarget.

- [ ] **Step 4: Implémenter le modèle**

```ruby
# app/models/schema_target.rb
class SchemaTarget < ApplicationRecord
  belongs_to :demarche
  has_many :schema_block_targets, dependent: :destroy

  enum :target_type, { baserow: 'baserow', grist: 'grist' }, validate: true

  validates :demarche_id, uniqueness: { scope: :target_type }
end
```

- [ ] **Step 5: Lancer le spec, attendre PASS**

```bash
bundle exec rspec spec/models/schema_target_spec.rb
```

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A
git add app/models/schema_target.rb spec/models/schema_target_spec.rb spec/factories/
git commit -m "feat(refonte): modèle SchemaTarget avec validations + factory"
git push
```

### Task B4 : Modèle `SchemaBlockTarget` + spec

**Files:**
- Create: `app/models/schema_block_target.rb`
- Create: `spec/models/schema_block_target_spec.rb`
- Create: `spec/factories/schema_block_targets.rb`

- [ ] **Step 1: Spec failing**

```ruby
# spec/models/schema_block_target_spec.rb
require 'rails_helper'

RSpec.describe SchemaBlockTarget, type: :model do
  let(:schema_target) { create(:schema_target) }

  it 'est valide avec schema_target + block_descriptor_id' do
    btarget = SchemaBlockTarget.new(
      schema_target: schema_target,
      block_descriptor_id: 'Q2hhbXAtMTIzNA=='
    )
    expect(btarget).to be_valid
  end

  it 'exige block_descriptor_id' do
    btarget = SchemaBlockTarget.new(schema_target: schema_target)
    expect(btarget).not_to be_valid
  end

  it 'unicité (schema_target_id, block_descriptor_id)' do
    SchemaBlockTarget.create!(schema_target: schema_target, block_descriptor_id: 'abc')
    duplicate = SchemaBlockTarget.new(schema_target: schema_target, block_descriptor_id: 'abc')
    expect(duplicate).not_to be_valid
  end

  it 'belongs_to schema_target' do
    assoc = described_class.reflect_on_association(:schema_target)
    expect(assoc.macro).to eq(:belongs_to)
  end
end
```

```ruby
# spec/factories/schema_block_targets.rb
FactoryBot.define do
  factory :schema_block_target do
    association :schema_target
    sequence(:block_descriptor_id) { |n| "Q2hhbXAtI#{n}" }
    sequence(:backend_table_id) { |n| "table_#{n}" }
  end
end
```

- [ ] **Step 2: Lancer, attendre FAIL**

```bash
bundle exec rspec spec/models/schema_block_target_spec.rb
```

- [ ] **Step 3: Implémenter**

```ruby
# app/models/schema_block_target.rb
class SchemaBlockTarget < ApplicationRecord
  belongs_to :schema_target

  validates :block_descriptor_id, presence: true,
                                   uniqueness: { scope: :schema_target_id }
end
```

- [ ] **Step 4: Lancer, attendre PASS**

```bash
bundle exec rspec spec/models/schema_block_target_spec.rb
```

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A
git add app/models/schema_block_target.rb spec/
git commit -m "feat(refonte): modèle SchemaBlockTarget avec validations + factory"
git push
```

### Task B5 : Demarche `has_many :schema_targets`

**Files:**
- Modify: `app/models/demarche.rb`
- Modify: `spec/models/demarche_spec.rb` (créer si absent)

- [ ] **Step 1: Spec failing**

Vérifier d'abord si `spec/models/demarche_spec.rb` existe (`ls spec/models/`). Sinon créer :

```ruby
# spec/models/demarche_spec.rb
require 'rails_helper'

RSpec.describe Demarche, type: :model do
  describe 'associations' do
    it 'has_many schema_targets dependent destroy' do
      assoc = described_class.reflect_on_association(:schema_targets)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end

    it 'destroy d\'une démarche cascade sur ses schema_targets' do
      demarche = create(:demarche)
      create(:schema_target, demarche: demarche)
      expect { demarche.destroy }.to change(SchemaTarget, :count).by(-1)
    end
  end
end
```

- [ ] **Step 2: Lancer, attendre FAIL**

```bash
bundle exec rspec spec/models/demarche_spec.rb
```

- [ ] **Step 3: Modifier Demarche**

Ajouter dans `app/models/demarche.rb` (parmi les autres `has_many`) :

```ruby
has_many :schema_targets, dependent: :destroy
```

- [ ] **Step 4: Lancer, attendre PASS**

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A
git add app/models/demarche.rb spec/models/demarche_spec.rb
git commit -m "feat(refonte): Demarche has_many :schema_targets"
git push
```

---

## Phase C — Backend abstraction (3-4 jours)

Nouveau namespace `SchemaBuilders` consolidant `MesDemarchesToBaserow::*` et `MesDemarchesToGrist::*`. La logique métier ne change pas — on extrait l'interface `Target` et on rebranchent les builders sur cette interface. Les anciens namespaces restent en place pendant cette phase (suppression en Phase K).

### Task C1 : Module `SchemaBuilders::Target` (interface)

**Files:**
- Create: `app/lib/schema_builders/target.rb`
- Create: `spec/lib/schema_builders/target_spec.rb`

- [ ] **Step 1: Spec failing**

```ruby
# spec/lib/schema_builders/target_spec.rb
require 'rails_helper'

RSpec.describe SchemaBuilders::Target do
  let(:dummy_class) do
    Class.new { include SchemaBuilders::Target }
  end

  let(:instance) { dummy_class.new }

  %i[list_workspaces list_applications list_tables
     create_table update_fields table_exists? field_exists?].each do |method|
    it "déclare la méthode #{method}" do
      expect(instance).to respond_to(method)
    end

    it "##{method} raise NotImplementedError par défaut" do
      args = instance.method(method).arity.positive? ? Array.new(instance.method(method).arity) : []
      expect { instance.public_send(method, *args) }.to raise_error(NotImplementedError)
    end
  end
end
```

- [ ] **Step 2: Lancer, attendre FAIL**

- [ ] **Step 3: Implémenter**

```ruby
# app/lib/schema_builders/target.rb
module SchemaBuilders
  module Target
    def list_workspaces
      raise NotImplementedError
    end

    def list_applications(workspace_id)
      raise NotImplementedError
    end

    def list_tables(application_id)
      raise NotImplementedError
    end

    def create_table(application_id, name, fields)
      raise NotImplementedError
    end

    def update_fields(table_id, fields)
      raise NotImplementedError
    end

    def table_exists?(application_id, name)
      raise NotImplementedError
    end

    def field_exists?(table_id, name)
      raise NotImplementedError
    end
  end
end
```

- [ ] **Step 4: Lancer, attendre PASS**

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A
git add app/lib/schema_builders/ spec/lib/schema_builders/
git commit -m "feat(refonte): interface SchemaBuilders::Target"
git push
```

### Task C2 : `SchemaBuilders::BaserowTarget`

**Files:**
- Create: `app/lib/schema_builders/baserow_target.rb`
- Create: `spec/lib/schema_builders/baserow_target_spec.rb`

Adapte `Baserow::StructureClient` (existant) à l'interface `Target`.

- [ ] **Step 1: Cartographier l'existant**

Lire `app/lib/baserow/structure_client.rb` et `app/lib/mes_demarches_to_baserow/schema_builder.rb`. Identifier les méthodes exposées (list workspaces, applications, tables ; create_table ; etc.).

- [ ] **Step 2: Spec avec doubles**

```ruby
# spec/lib/schema_builders/baserow_target_spec.rb
require 'rails_helper'

RSpec.describe SchemaBuilders::BaserowTarget do
  let(:structure_client) { instance_double(Baserow::StructureClient) }
  let(:target) { described_class.new(structure_client: structure_client) }

  it 'est un SchemaBuilders::Target' do
    expect(target).to be_a(SchemaBuilders::Target)
  end

  describe '#list_workspaces' do
    it 'délègue au StructureClient' do
      allow(structure_client).to receive(:list_workspaces).and_return([{ 'id' => 42, 'name' => 'WS' }])
      expect(target.list_workspaces).to eq([{ 'id' => 42, 'name' => 'WS' }])
    end
  end

  describe '#list_applications' do
    it 'délègue avec workspace_id' do
      allow(structure_client).to receive(:list_applications).with(42).and_return([])
      target.list_applications(42)
      expect(structure_client).to have_received(:list_applications).with(42)
    end
  end

  describe '#table_exists?' do
    it 'cherche par nom dans les tables d\'une application' do
      allow(structure_client).to receive(:list_tables).with(17).and_return(
        [{ 'id' => 1, 'name' => 'Existing' }, { 'id' => 2, 'name' => 'Other' }]
      )
      expect(target.table_exists?(17, 'Existing')).to be true
      expect(target.table_exists?(17, 'Missing')).to be false
    end
  end
end
```

- [ ] **Step 3: Lancer, attendre FAIL**

- [ ] **Step 4: Implémenter**

```ruby
# app/lib/schema_builders/baserow_target.rb
module SchemaBuilders
  class BaserowTarget
    include Target

    def initialize(structure_client: Baserow::StructureClient.new)
      @client = structure_client
    end

    def list_workspaces
      @client.list_workspaces
    end

    def list_applications(workspace_id)
      @client.list_applications(workspace_id)
    end

    def list_tables(application_id)
      @client.list_tables(application_id)
    end

    def create_table(application_id, name, fields)
      @client.create_table(application_id: application_id, name: name, fields: fields)
    end

    def update_fields(table_id, fields)
      @client.update_table_fields(table_id, fields)
    end

    def table_exists?(application_id, name)
      list_tables(application_id).any? { |t| t['name'] == name }
    end

    def field_exists?(table_id, name)
      @client.list_fields(table_id).any? { |f| f['name'] == name }
    end
  end
end
```

Note : adapter les noms de méthodes (`list_workspaces`, `list_applications`, etc.) à ce qui existe vraiment dans `Baserow::StructureClient`. Si certaines n'existent pas, les ajouter au client OU appeler directement les méthodes existantes (l'adapter encapsule cette différence).

- [ ] **Step 5: Lancer, attendre PASS**

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A
git add app/lib/schema_builders/baserow_target.rb spec/
git commit -m "feat(refonte): SchemaBuilders::BaserowTarget (adapter Baserow::StructureClient)"
git push
```

### Task C3 : `SchemaBuilders::GristTarget`

**Files:**
- Create: `app/lib/schema_builders/grist_target.rb`
- Create: `spec/lib/schema_builders/grist_target_spec.rb`

Même pattern que BaserowTarget mais sur le client Grist existant.

- [ ] **Step 1: Cartographier l'existant Grist**

Lire `app/lib/grist/*.rb` ou `app/lib/mes_demarches_to_grist/*.rb` pour identifier le client utilisé.

- [ ] **Step 2: Spec avec doubles** (structure identique à C2, adapter aux méthodes Grist)

- [ ] **Step 3: Lancer FAIL**

- [ ] **Step 4: Implémenter**

```ruby
# app/lib/schema_builders/grist_target.rb
module SchemaBuilders
  class GristTarget
    include Target

    def initialize(grist_client: Grist::Client.new)
      @client = grist_client
    end

    def list_workspaces
      @client.list_orgs.flat_map { |org| @client.list_workspaces(org['id']) }
    end

    def list_applications(workspace_id)
      @client.list_docs(workspace_id)
    end

    def list_tables(application_id)
      @client.list_tables(application_id)
    end

    def create_table(application_id, name, fields)
      @client.create_table(application_id, name, fields)
    end

    def update_fields(table_id, fields)
      @client.update_fields(table_id, fields)
    end

    def table_exists?(application_id, name)
      list_tables(application_id).any? { |t| t['name'] == name || t['id'] == name }
    end

    def field_exists?(table_id, name)
      @client.list_columns(table_id).any? { |c| c['id'] == name }
    end
  end
end
```

Adapter aux vraies méthodes du client Grist.

- [ ] **Step 5: PASS + Commit**

```bash
git add app/lib/schema_builders/grist_target.rb spec/
git commit -m "feat(refonte): SchemaBuilders::GristTarget"
git push
```

### Task C4 : `SchemaBuilders::TypeMapper` (consolider)

**Files:**
- Create: `app/lib/schema_builders/type_mapper.rb`
- Create: `spec/lib/schema_builders/type_mapper_spec.rb`

Consolide `MesDemarchesToBaserow::TypeMapper` et `MesDemarchesToGrist::TypeMapper`.

- [ ] **Step 1: Lire les deux TypeMappers existants** et identifier différences.

- [ ] **Step 2: Spec failing** : couvrir au moins 5 types Mes-Démarches (text, integer_number, date, drop_down_list, repetition) avec assertion sur la valeur Baserow ET Grist.

```ruby
# spec/lib/schema_builders/type_mapper_spec.rb
require 'rails_helper'

RSpec.describe SchemaBuilders::TypeMapper do
  describe '.for(:baserow)' do
    let(:mapper) { described_class.for(:baserow) }

    it { expect(mapper.call('text')).to eq('text') }
    it { expect(mapper.call('integer_number')).to eq('number') }
    it { expect(mapper.call('date')).to eq('date') }
    it { expect(mapper.call('drop_down_list')).to eq('single_select') }
  end

  describe '.for(:grist)' do
    let(:mapper) { described_class.for(:grist) }

    it { expect(mapper.call('text')).to eq('Text') }
    it { expect(mapper.call('integer_number')).to eq('Int') }
    it { expect(mapper.call('date')).to eq('Date') }
    it { expect(mapper.call('drop_down_list')).to eq('Choice') }
  end

  it 'raise pour cible inconnue' do
    expect { described_class.for(:notion) }.to raise_error(ArgumentError, /unknown target/)
  end
end
```

- [ ] **Step 3: Implémenter**

```ruby
# app/lib/schema_builders/type_mapper.rb
module SchemaBuilders
  class TypeMapper
    BASEROW_MAP = {
      'text' => 'text',
      'integer_number' => 'number',
      # ... copier-coller depuis MesDemarchesToBaserow::TypeMapper
    }.freeze

    GRIST_MAP = {
      'text' => 'Text',
      'integer_number' => 'Int',
      # ... copier-coller depuis MesDemarchesToGrist::TypeMapper
    }.freeze

    def self.for(target)
      case target
      when :baserow then new(BASEROW_MAP)
      when :grist then new(GRIST_MAP)
      else raise ArgumentError, "unknown target #{target}"
      end
    end

    def initialize(map)
      @map = map
    end

    def call(mes_demarches_type)
      @map.fetch(mes_demarches_type) { @map.fetch('text') }
    end
  end
end
```

Renseigner les vrais mappings depuis les deux TypeMappers existants — c'est mécanique mais demander attention pour ne pas perdre un cas.

- [ ] **Step 4: PASS + Commit**

```bash
git add app/lib/schema_builders/type_mapper.rb spec/
git commit -m "feat(refonte): SchemaBuilders::TypeMapper consolidé (Baserow + Grist)"
git push
```

### Task C5 : `SchemaBuilders::FieldFilter`

**Files:**
- Create: `app/lib/schema_builders/field_filter.rb`
- Create: `spec/lib/schema_builders/field_filter_spec.rb`

Consolide les deux FieldFilters existants. Pattern identique à C4 (lire les deux, écrire spec, implémenter, passer).

- [ ] **Step 1-5:** identique pattern. Commit final :

```bash
git commit -m "feat(refonte): SchemaBuilders::FieldFilter consolidé"
git push
```

### Task C6 : `SchemaBuilders::MainTableBuilder`

**Files:**
- Create: `app/lib/schema_builders/main_table_builder.rb`
- Create: `spec/lib/schema_builders/main_table_builder_spec.rb`

Builder agnostique de cible. Prend un `Target` et expose `preview(demarche_descriptor)` + `build!(demarche_descriptor)`.

- [ ] **Step 1: Cartographier**

Lire `app/lib/mes_demarches_to_baserow/schema_builder.rb` et `app/lib/mes_demarches_to_grist/schema_builder.rb` côte à côte. Extraire la logique commune (mapping des champs, structure des fields, etc.).

- [ ] **Step 2: Spec**

```ruby
# spec/lib/schema_builders/main_table_builder_spec.rb
require 'rails_helper'

RSpec.describe SchemaBuilders::MainTableBuilder do
  let(:target) { instance_double(SchemaBuilders::BaserowTarget) }
  let(:type_mapper) { SchemaBuilders::TypeMapper.for(:baserow) }
  let(:field_filter) { instance_double(SchemaBuilders::FieldFilter, call: true) }
  let(:builder) { described_class.new(target: target, type_mapper: type_mapper, field_filter: field_filter) }

  let(:demarche_descriptor) do
    OpenStruct.new(
      champ_descriptors: [
        OpenStruct.new(id: 'c1', label: 'Nom', __typename: 'TextChampDescriptor'),
        OpenStruct.new(id: 'c2', label: 'Montant', __typename: 'IntegerChampDescriptor')
      ]
    )
  end

  describe '#preview' do
    it 'retourne la liste des champs avec leur type cible' do
      allow(field_filter).to receive(:call).and_return(true)
      preview = builder.preview(demarche_descriptor, application_id: 17, table_name: 'Dossiers')

      expect(preview[:table_name]).to eq('Dossiers')
      expect(preview[:fields]).to include(
        hash_including(name: 'Nom', type: 'text'),
        hash_including(name: 'Montant', type: 'number')
      )
    end

    it 'skip les champs filtrés' do
      allow(field_filter).to receive(:call) { |c| c.id != 'c2' }
      preview = builder.preview(demarche_descriptor, application_id: 17, table_name: 'Dossiers')

      expect(preview[:fields].map { |f| f[:name] }).to eq(['Nom'])
    end
  end

  describe '#build!' do
    it 'appelle target.create_table si la table n\'existe pas' do
      allow(target).to receive(:table_exists?).and_return(false)
      allow(target).to receive(:create_table).and_return({ 'id' => 99 })

      result = builder.build!(demarche_descriptor, application_id: 17, table_name: 'Dossiers')
      expect(target).to have_received(:create_table).with(17, 'Dossiers', kind_of(Array))
      expect(result[:table_id]).to eq(99)
    end

    it 'appelle target.update_fields si la table existe déjà' do
      allow(target).to receive(:table_exists?).and_return(true)
      allow(target).to receive(:list_tables).and_return([{ 'id' => 99, 'name' => 'Dossiers' }])
      allow(target).to receive(:update_fields).and_return(true)

      builder.build!(demarche_descriptor, application_id: 17, table_name: 'Dossiers')
      expect(target).to have_received(:update_fields).with(99, kind_of(Array))
    end
  end
end
```

- [ ] **Step 3: Implémenter**

```ruby
# app/lib/schema_builders/main_table_builder.rb
module SchemaBuilders
  class MainTableBuilder
    def initialize(target:, type_mapper:, field_filter:)
      @target = target
      @type_mapper = type_mapper
      @field_filter = field_filter
    end

    def preview(demarche_descriptor, application_id:, table_name:)
      fields = build_fields(demarche_descriptor)
      { table_name: table_name, application_id: application_id, fields: fields }
    end

    def build!(demarche_descriptor, application_id:, table_name:)
      fields = build_fields(demarche_descriptor)

      if @target.table_exists?(application_id, table_name)
        existing = @target.list_tables(application_id).find { |t| t['name'] == table_name }
        @target.update_fields(existing['id'], fields)
        { table_id: existing['id'], action: :updated }
      else
        created = @target.create_table(application_id, table_name, fields)
        { table_id: created['id'], action: :created }
      end
    end

    private

    def build_fields(demarche_descriptor)
      demarche_descriptor.champ_descriptors
        .select { |c| @field_filter.call(c) }
        .map { |c| { name: c.label, type: @type_mapper.call(mes_demarches_type_for(c)) } }
    end

    def mes_demarches_type_for(champ)
      champ.__typename.sub('ChampDescriptor', '').downcase
    end
  end
end
```

Note : adapter `mes_demarches_type_for` selon la convention réelle des `__typename` GraphQL utilisés dans le code existant (`TextChampDescriptor` → `text`, etc.).

- [ ] **Step 4: PASS + Commit**

```bash
git add app/lib/schema_builders/main_table_builder.rb spec/
git commit -m "feat(refonte): SchemaBuilders::MainTableBuilder agnostique de cible"
git push
```

### Task C7 : `SchemaBuilders::AvisBuilder`

**Files:**
- Create: `app/lib/schema_builders/avis_builder.rb`
- Create: `spec/lib/schema_builders/avis_builder_spec.rb`

Même structure que C6 mais pour la table Avis. Grist : raise NotImplementedError pour l'instant.

- [ ] **Step 1: Cartographier `MesDemarchesToBaserow::AvisTableBuilder`**

- [ ] **Step 2: Spec**

Inclure un test :

```ruby
it 'raise NotImplementedError si target est Grist' do
  grist_target = SchemaBuilders::GristTarget.new
  builder = described_class.new(target: grist_target, type_mapper: SchemaBuilders::TypeMapper.for(:grist))
  expect { builder.preview(demarche_descriptor, application_id: 17) }
    .to raise_error(NotImplementedError, /Avis non supporté/)
end
```

- [ ] **Step 3: Implémenter**

```ruby
# app/lib/schema_builders/avis_builder.rb
module SchemaBuilders
  class AvisBuilder
    AVIS_TABLE_NAME = 'Avis'.freeze
    AVIS_FIELDS = [
      { name: 'Dossier', type: 'text' },
      { name: 'Email', type: 'email' },
      { name: 'Question', type: 'long_text' },
      { name: 'Réponse', type: 'long_text' },
      { name: 'Date demande', type: 'date' },
      { name: 'Date réponse', type: 'date' }
    ].freeze

    def initialize(target:, type_mapper:)
      @target = target
      @type_mapper = type_mapper
      @target_kind = target_kind_for(target)
    end

    def preview(demarche_descriptor, application_id:)
      check_supported!
      { table_name: AVIS_TABLE_NAME, fields: mapped_fields }
    end

    def build!(demarche_descriptor, application_id:)
      check_supported!
      if @target.table_exists?(application_id, AVIS_TABLE_NAME)
        existing = @target.list_tables(application_id).find { |t| t['name'] == AVIS_TABLE_NAME }
        @target.update_fields(existing['id'], mapped_fields)
        { table_id: existing['id'], action: :updated }
      else
        created = @target.create_table(application_id, AVIS_TABLE_NAME, mapped_fields)
        { table_id: created['id'], action: :created }
      end
    end

    private

    def mapped_fields
      AVIS_FIELDS.map { |f| f.merge(type: @type_mapper.call(f[:type])) }
    end

    def check_supported!
      raise NotImplementedError, 'Avis non supporté par Grist pour l\'instant' if @target_kind == :grist
    end

    def target_kind_for(target)
      case target
      when SchemaBuilders::BaserowTarget then :baserow
      when SchemaBuilders::GristTarget then :grist
      else :unknown
      end
    end
  end
end
```

- [ ] **Step 4: PASS + Commit**

```bash
git add app/lib/schema_builders/avis_builder.rb spec/
git commit -m "feat(refonte): SchemaBuilders::AvisBuilder (Grist non supporté pour l'instant)"
git push
```

### Task C8 : `SchemaBuilders::BlockBuilder`

**Files:**
- Create: `app/lib/schema_builders/block_builder.rb`
- Create: `spec/lib/schema_builders/block_builder_spec.rb`

Pour les blocs répétables. Une table par bloc.

- [ ] **Step 1: Cartographier `RepetableBlockBuilder` existants** (Baserow + Grist).

- [ ] **Step 2: Spec** : inclure un test "preview retourne une entrée par bloc répétable trouvé dans la démarche".

- [ ] **Step 3: Implémenter**

```ruby
# app/lib/schema_builders/block_builder.rb
module SchemaBuilders
  class BlockBuilder
    def initialize(target:, type_mapper:, field_filter:)
      @target = target
      @type_mapper = type_mapper
      @field_filter = field_filter
    end

    def preview(demarche_descriptor, application_id:)
      blocks_from(demarche_descriptor).map do |block|
        {
          block_descriptor_id: block.id,
          table_name: block.label,
          fields: fields_for(block)
        }
      end
    end

    def build!(demarche_descriptor, application_id:)
      preview(demarche_descriptor, application_id: application_id).map do |spec|
        if @target.table_exists?(application_id, spec[:table_name])
          existing = @target.list_tables(application_id).find { |t| t['name'] == spec[:table_name] }
          @target.update_fields(existing['id'], spec[:fields])
          spec.merge(table_id: existing['id'], action: :updated)
        else
          created = @target.create_table(application_id, spec[:table_name], spec[:fields])
          spec.merge(table_id: created['id'], action: :created)
        end
      end
    end

    private

    def blocks_from(demarche_descriptor)
      demarche_descriptor.champ_descriptors.select { |c| c.__typename == 'RepetitionChampDescriptor' }
    end

    def fields_for(block)
      block.champ_descriptors.select { |c| @field_filter.call(c) }.map do |c|
        { name: c.label, type: @type_mapper.call(c.__typename.sub('ChampDescriptor', '').downcase) }
      end
    end
  end
end
```

- [ ] **Step 4: PASS + Commit**

```bash
git add app/lib/schema_builders/block_builder.rb spec/
git commit -m "feat(refonte): SchemaBuilders::BlockBuilder"
git push
```

---

## Phase D — Controller + routes + dashboard skeleton (2 jours)

### Task D1 : Routes scopées à la démarche

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Lire les routes actuelles**

Vérifier l'emplacement des routes `admin/baserow_schema/*` (à conserver pour l'instant).

- [ ] **Step 2: Ajouter les nouvelles routes**

```ruby
# config/routes.rb — dans le bloc Rails.application.routes.draw
namespace :admin do
  resources :demarches, only: [], param: :demarche_id do
    resource :schema, only: [:show], controller: 'schema_builder' do
      resources :targets, only: [:create, :destroy], param: :target_type

      scope ':target' do
        post 'main_table/preview', to: 'schema_builder#preview_main_table'
        post 'main_table/build', to: 'schema_builder#build_main_table'
        post 'avis/preview', to: 'schema_builder#preview_avis'
        post 'avis/build', to: 'schema_builder#build_avis'
        post 'blocks/preview', to: 'schema_builder#preview_blocks'
        post 'blocks/build', to: 'schema_builder#build_blocks'
      end
    end
  end
end
```

Note : ne PAS retirer les routes `admin/baserow_schema` ni `admin/grist_schema` à ce stade.

- [ ] **Step 3: Vérifier**

```bash
bin/rails routes | grep -E "schema|demarches" | head -30
```

Attendu : voir les nouvelles routes apparaître à côté des anciennes.

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb
git commit -m "feat(refonte): routes Admin::SchemaBuilder scopées démarche"
git push
```

### Task D2 : `Admin::SchemaBuilderController#show` + spec

**Files:**
- Create: `app/controllers/admin/schema_builder_controller.rb`
- Create: `spec/controllers/admin/schema_builder_controller_spec.rb`

- [ ] **Step 1: Spec failing**

```ruby
# spec/controllers/admin/schema_builder_controller_spec.rb
require 'rails_helper'

RSpec.describe Admin::SchemaBuilderController, type: :controller do
  let(:user) { create(:user) }
  let(:demarche) { create(:demarche) }

  before { sign_in user }

  describe 'GET #show' do
    it 'rend la page (200)' do
      get :show, params: { demarche_demarche_id: demarche.id }
      expect(response).to have_http_status(:ok)
    end

    it 'assigne @demarche' do
      get :show, params: { demarche_demarche_id: demarche.id }
      expect(assigns(:demarche)).to eq(demarche)
    end

    it 'assigne @schema_targets (vide initialement)' do
      get :show, params: { demarche_demarche_id: demarche.id }
      expect(assigns(:schema_targets)).to eq([])
    end

    it '404 si la démarche n\'existe pas' do
      expect { get :show, params: { demarche_demarche_id: 99_999 } }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
```

Note : vérifier que `create(:user)` fonctionne avec Devise (factory à adapter si besoin avec `confirmed_at: Time.current` selon la config Devise du projet).

- [ ] **Step 2: Lancer FAIL**

- [ ] **Step 3: Implémenter**

```ruby
# app/controllers/admin/schema_builder_controller.rb
module Admin
  class SchemaBuilderController < ApplicationController
    before_action :authenticate_user!
    before_action :set_demarche

    def show
      @schema_targets = @demarche.schema_targets.order(:target_type)
    end

    private

    def set_demarche
      @demarche = Demarche.find(params[:demarche_demarche_id])
    end
  end
end
```

- [ ] **Step 4: Créer la vue squelette**

```haml
-# app/views/admin/schema_builder/show.html.haml
%h1= "Démarche ##{@demarche.id} — #{@demarche.libelle}"

%section.schema-builder{data: { controller: 'schema-builder' }}
  %p Aucune cible configurée.
```

- [ ] **Step 5: Lancer PASS**

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A
git add app/controllers/admin/schema_builder_controller.rb app/views/admin/schema_builder/show.html.haml spec/
git commit -m "feat(refonte): Admin::SchemaBuilderController#show + vue squelette"
git push
```

### Task D3 : System test du show

**Files:**
- Create: `spec/system/admin/schema_builder/dashboard_spec.rb`

- [ ] **Step 1: Spec**

```ruby
# spec/system/admin/schema_builder/dashboard_spec.rb
require 'rails_helper'

RSpec.describe 'Schema builder dashboard', type: :system, js: true do
  let(:user) { create(:user) }
  let(:demarche) { create(:demarche) }

  before do
    sign_in user
    visit "/admin/demarches/#{demarche.id}/schema"
  end

  it 'affiche le titre de la démarche' do
    expect(page).to have_content(demarche.libelle)
  end

  it 'indique "Aucune cible configurée" quand aucune SchemaTarget existe' do
    expect(page).to have_content('Aucune cible configurée')
  end
end
```

Note : `sign_in user` nécessite `Warden::Test::Helpers` inclus pour les system specs Devise. Vérifier que `spec/rails_helper.rb` contient :

```ruby
RSpec.configure do |config|
  config.include Warden::Test::Helpers, type: :system
  config.before(:each, type: :system) { Warden.test_mode! }
  config.after(:each, type: :system) { Warden.test_reset! }
end
```

- [ ] **Step 2: Lancer PASS**

```bash
bundle exec rspec spec/system/admin/schema_builder/
```

- [ ] **Step 3: Commit**

```bash
git add spec/system/
git commit -m "test(refonte): system test du dashboard skeleton"
git push
```

---

## Phase E — Target tabs + cascade (3-4 jours)

L'utilisateur peut ajouter Baserow ET/OU Grist comme cible pour une démarche. Onglets dynamiques. À l'intérieur d'un onglet, cascade workspace → application → table.

### Task E1 : Endpoint `POST /targets` + spec

**Files:**
- Modify: `app/controllers/admin/schema_builder_controller.rb`
- Create: `app/views/admin/schema_builder/_target_tabs.html.haml`
- Modify: `spec/controllers/admin/schema_builder_controller_spec.rb`

- [ ] **Step 1: Spec failing**

Ajouter dans le spec controller :

```ruby
describe 'POST #create_target' do
  it 'crée une SchemaTarget pour la démarche' do
    expect {
      post :create_target, params: { demarche_demarche_id: demarche.id, target_type: 'baserow' }
    }.to change { demarche.schema_targets.count }.by(1)
  end

  it 'refuse un target_type inconnu' do
    post :create_target, params: { demarche_demarche_id: demarche.id, target_type: 'notion' }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'refuse un doublon' do
    create(:schema_target, demarche: demarche, target_type: 'baserow')
    post :create_target, params: { demarche_demarche_id: demarche.id, target_type: 'baserow' }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] **Step 2: Lancer FAIL**

- [ ] **Step 3: Implémenter dans le controller**

```ruby
def create_target
  target = @demarche.schema_targets.new(target_type: params[:target_type])
  if target.save
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace('schema-targets', partial: 'target_tabs', locals: { demarche: @demarche, targets: @demarche.schema_targets.order(:target_type) }) }
      format.html { redirect_to admin_demarche_schema_path(demarche_id: @demarche.id) }
    end
  else
    head :unprocessable_entity
  end
end

def destroy_target
  target = @demarche.schema_targets.find_by!(target_type: params[:target_type])
  target.destroy!
  respond_to do |format|
    format.turbo_stream { render turbo_stream: turbo_stream.replace('schema-targets', partial: 'target_tabs', locals: { demarche: @demarche, targets: @demarche.schema_targets.order(:target_type) }) }
    format.html { redirect_to admin_demarche_schema_path(demarche_id: @demarche.id) }
  end
end
```

Et ajuster les routes en D1 pour utiliser `param: :target_type` correctement :

```ruby
# config/routes.rb (revoir si nécessaire pour matcher le contrôleur)
post 'targets', to: 'schema_builder#create_target'
delete 'targets/:target_type', to: 'schema_builder#destroy_target'
```

- [ ] **Step 4: PASS + Commit**

```bash
git add -A
git commit -m "feat(refonte): create/destroy SchemaTarget avec Turbo Stream"
git push
```

### Task E2 : Partial `_target_tabs` + boutons d'ajout

**Files:**
- Create: `app/views/admin/schema_builder/_target_tabs.html.haml`
- Modify: `app/views/admin/schema_builder/show.html.haml`

- [ ] **Step 1: Écrire le partial**

```haml
-# app/views/admin/schema_builder/_target_tabs.html.haml
%div#schema-targets{data: { controller: 'target-tabs' }}
  %nav.nav.nav-tabs
    - targets.each_with_index do |target, idx|
      %a.nav-link{href: "##{target.target_type}-panel", class: ('active' if idx.zero?), data: { action: 'click->target-tabs#switch' }}
        = target.target_type.titleize
        = button_to '✕', admin_demarche_schema_target_path(demarche_demarche_id: demarche.id, target_type: target.target_type), method: :delete, form: { data: { turbo_confirm: 'Supprimer cette cible ?' } }, class: 'btn-close'
  .tab-content
    - targets.each_with_index do |target, idx|
      .tab-pane{id: "#{target.target_type}-panel", class: ('show active' if idx.zero?), data: { target_tabs_target: 'panel' }}
        = render 'target_panel', target: target

  - missing_types = %w[baserow grist] - targets.map(&:target_type)
  - if missing_types.any?
    %div.mt-3
      - missing_types.each do |type|
        = button_to "+ Ajouter #{type.titleize}", admin_demarche_schema_targets_path(demarche_demarche_id: demarche.id, target_type: type), method: :post, class: 'btn btn-outline-primary me-2'
```

- [ ] **Step 2: Créer un partial vide `_target_panel`**

```haml
-# app/views/admin/schema_builder/_target_panel.html.haml
%div{data: { controller: 'cascade-select', cascade_select_target_type_value: target.target_type, cascade_select_demarche_id_value: target.demarche_id }}
  %p Panel #{target.target_type} — workspace/app/table TBD (Task E4)
```

- [ ] **Step 3: Modifier `show.html.haml`**

```haml
-# app/views/admin/schema_builder/show.html.haml
%h1= "Démarche ##{@demarche.id} — #{@demarche.libelle}"

%section.schema-builder{data: { controller: 'schema-builder' }}
  = render 'target_tabs', demarche: @demarche, targets: @schema_targets
```

- [ ] **Step 4: System test**

```ruby
# spec/system/admin/schema_builder/dashboard_spec.rb (ajouter)
context 'avec une SchemaTarget existante' do
  before do
    create(:schema_target, demarche: demarche, target_type: 'baserow')
    visit "/admin/demarches/#{demarche.id}/schema"
  end

  it 'affiche l\'onglet Baserow' do
    expect(page).to have_selector('a.nav-link', text: 'Baserow')
  end

  it 'propose d\'ajouter Grist' do
    expect(page).to have_button('+ Ajouter Grist')
  end
end

context 'ajout d\'une cible via le bouton' do
  it 'fait apparaître l\'onglet via Turbo Stream' do
    visit "/admin/demarches/#{demarche.id}/schema"
    click_button '+ Ajouter Baserow'
    expect(page).to have_selector('a.nav-link', text: 'Baserow')
  end
end
```

- [ ] **Step 5: Lancer PASS**

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(refonte): partial target_tabs avec boutons d'ajout et Turbo Stream"
git push
```

### Task E3 : Stimulus controller `target_tabs`

**Files:**
- Create: `app/javascript/controllers/schema_builder/target_tabs_controller.js`
- Modify: `app/javascript/controllers/index.js` (auto-register si stimulus-loading utilisé)

- [ ] **Step 1: Écrire le controller**

```javascript
// app/javascript/controllers/schema_builder/target_tabs_controller.js
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
```

- [ ] **Step 2: Enregistrer dans Stimulus**

Vérifier `app/javascript/controllers/index.js`. Si stimulus-loading via importmap (avec `eagerLoadControllersFrom("controllers", application)`), le contrôleur s'auto-enregistre. Sinon ajouter manuellement :

```javascript
import TargetTabsController from "./schema_builder/target_tabs_controller"
application.register("target-tabs", TargetTabsController)
```

- [ ] **Step 3: Pin via importmap si nécessaire**

```bash
bin/importmap pin "./controllers/schema_builder/target_tabs_controller"
```

- [ ] **Step 4: Vérifier dans le system test E2** que le switch fonctionne :

```ruby
it 'le switch d\'onglet ne recharge pas la page' do
  create(:schema_target, demarche: demarche, target_type: 'baserow')
  create(:schema_target, demarche: demarche, target_type: 'grist')
  visit "/admin/demarches/#{demarche.id}/schema"

  click_link 'Grist'
  expect(page).to have_selector('#grist-panel.show.active')
  expect(page).not_to have_selector('#baserow-panel.show.active')
end
```

- [ ] **Step 5: PASS + Commit**

```bash
git add -A
git commit -m "feat(refonte): Stimulus target_tabs controller"
git push
```

### Task E4 : Cascade workspace → application → table

**Files:**
- Create: `app/javascript/controllers/schema_builder/cascade_select_controller.js`
- Modify: `app/views/admin/schema_builder/_target_panel.html.haml`
- Modify: `app/controllers/admin/schema_builder_controller.rb` (endpoints liste)

- [ ] **Step 1: Endpoints liste**

Ajouter dans le controller (et les routes) :

```ruby
# config/routes.rb (dans le scope schema)
get 'targets/:target_type/workspaces',                   to: 'schema_builder#list_workspaces',   as: :list_workspaces
get 'targets/:target_type/applications/:workspace_id',   to: 'schema_builder#list_applications', as: :list_applications
get 'targets/:target_type/tables/:application_id',       to: 'schema_builder#list_tables',       as: :list_tables
```

```ruby
# Controller
def list_workspaces
  render json: target_adapter.list_workspaces
end

def list_applications
  render json: target_adapter.list_applications(params[:workspace_id])
end

def list_tables
  render json: target_adapter.list_tables(params[:application_id])
end

private

def target_adapter
  case params[:target_type]
  when 'baserow' then SchemaBuilders::BaserowTarget.new
  when 'grist' then SchemaBuilders::GristTarget.new
  else raise ActionController::ParameterMissing, "unknown target_type"
  end
end
```

- [ ] **Step 2: Specs controller**

Ajouter au spec controller des tests stubbant les targets via `allow_any_instance_of`. Ou mieux, injecter le target via une méthode override-able (`target_adapter`) et stubber dans le spec.

- [ ] **Step 3: Stimulus controller `cascade_select`**

```javascript
// app/javascript/controllers/schema_builder/cascade_select_controller.js
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
    if (!wsId) return
    const url = `/admin/demarches/${this.demarcheIdValue}/schema/targets/${this.targetTypeValue}/applications/${wsId}`
    const list = await this.#fetchJson(url)
    this.#populate(this.applicationTarget, list, "Sélectionnez une application")
    this.#reset(this.tableTarget, "Sélectionnez une table")
  }

  async onApplicationChange(event) {
    const appId = event.target.value
    if (!appId) return
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
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content
    await fetch(`/admin/demarches/${this.demarcheIdValue}/schema/targets/${this.targetTypeValue}/selection`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken, 'Accept': 'text/vnd.turbo-stream.html' },
      body: JSON.stringify(payload)
    })
  }

  async #fetchJson(url) {
    const res = await fetch(url, { headers: { 'Accept': 'application/json' } })
    return res.ok ? res.json() : []
  }

  #populate(selectEl, items, placeholder) {
    selectEl.innerHTML = `<option value="">${placeholder}</option>`
    items.forEach(item => {
      const opt = document.createElement('option')
      opt.value = item.id || item.external_id
      opt.textContent = item.name || item.label
      selectEl.appendChild(opt)
    })
  }

  #reset(selectEl, placeholder) {
    selectEl.innerHTML = `<option value="">${placeholder}</option>`
  }
}
```

- [ ] **Step 4: Endpoint PATCH `selection`**

```ruby
# Controller
def update_target_selection
  target = @demarche.schema_targets.find_by!(target_type: params[:target_type])
  target.update!(target_selection_params)
  head :ok
end

private

def target_selection_params
  params.permit(:workspace_external_id, :application_external_id, :main_table_external_id)
end
```

```ruby
# config/routes.rb
patch 'targets/:target_type/selection', to: 'schema_builder#update_target_selection'
```

- [ ] **Step 5: Mettre à jour `_target_panel.html.haml`**

```haml
-# app/views/admin/schema_builder/_target_panel.html.haml
%div{data: {
  controller: 'cascade-select',
  cascade_select_target_type_value: target.target_type,
  cascade_select_demarche_id_value: target.demarche_id,
  cascade_select_schema_target_id_value: target.id
}}
  %div.row.g-3.mt-3
    %div.col-md-4
      %label.form-label Workspace
      %select.form-select{data: { cascade_select_target: 'workspace', action: 'change->cascade-select#onWorkspaceChange change->cascade-select#onSelectionChange' }}
        %option{value: ''} Chargement…
    %div.col-md-4
      %label.form-label Application
      %select.form-select{data: { cascade_select_target: 'application', action: 'change->cascade-select#onApplicationChange change->cascade-select#onSelectionChange' }}
        %option{value: ''} —
    %div.col-md-4
      %label.form-label Table principale
      %select.form-select{data: { cascade_select_target: 'table', action: 'change->cascade-select#onSelectionChange' }}
        %option{value: ''} —

  %hr
  -# Sections du dashboard
  = render 'main_table_section', target: target
  = render 'avis_section', target: target
  = render 'blocks_section', target: target
```

- [ ] **Step 6: System test cascade**

```ruby
it 'la cascade charge les options de workspace', :js do
  stub_baserow_workspaces([{ id: 42, name: 'WS Test' }])
  create(:schema_target, demarche: demarche, target_type: 'baserow')
  visit "/admin/demarches/#{demarche.id}/schema"

  within('#baserow-panel') do
    expect(page).to have_select(nil, with_options: ['WS Test'])
  end
end
```

Définir un helper `stub_baserow_workspaces` qui stub la méthode `list_workspaces` de l'adapter via WebMock ou injection de double.

- [ ] **Step 7: PASS + Commit**

```bash
git add -A
git commit -m "feat(refonte): cascade workspace → application → table (Stimulus + endpoints JSON)"
git push
```

---

## Phase F — Main table section (2 jours)

### Task F1 : Partial `_main_table_section` + Turbo Frame

**Files:**
- Create: `app/views/admin/schema_builder/_main_table_section.html.haml`

- [ ] **Step 1: Écrire le partial**

```haml
-# app/views/admin/schema_builder/_main_table_section.html.haml
%turbo-frame{id: "main-table-#{target.id}"}
  %div.card.mt-3
    %div.card-header
      %h5.mb-0
        Table principale
        %span.badge.bg-secondary.ms-2= main_table_status_label(target)
    %div.card-body
      = button_to 'Preview', preview_main_table_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type), method: :post, class: 'btn btn-outline-primary me-2', data: { turbo_frame: "main-table-#{target.id}" }
      = button_to 'Build', build_main_table_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type), method: :post, class: 'btn btn-primary', data: { turbo_frame: "main-table-#{target.id}", turbo_confirm: 'Confirmer la création/maj de la table ?' }
```

- [ ] **Step 2: Helper pour le statut**

```ruby
# app/helpers/schema_builder_helper.rb
module SchemaBuilderHelper
  def main_table_status_label(target)
    if target.last_synced_at.present? && target.main_table_external_id.present?
      "Sync OK le #{l target.last_synced_at, format: :short}"
    else
      "Jamais sync"
    end
  end
end
```

- [ ] **Step 3: Spec helper**

```ruby
# spec/helpers/schema_builder_helper_spec.rb
require 'rails_helper'

RSpec.describe SchemaBuilderHelper do
  describe '#main_table_status_label' do
    it 'retourne "Jamais sync" sans last_synced_at' do
      target = build(:schema_target, last_synced_at: nil, main_table_external_id: nil)
      expect(helper.main_table_status_label(target)).to eq('Jamais sync')
    end

    it 'retourne la date formatée si sync' do
      target = build(:schema_target, last_synced_at: Time.zone.parse('2026-05-15 10:00'), main_table_external_id: '99')
      expect(helper.main_table_status_label(target)).to include('Sync OK')
    end
  end
end
```

- [ ] **Step 4: PASS + Commit**

```bash
git add -A
git commit -m "feat(refonte): partial main_table_section + helper statut"
git push
```

### Task F2 : Action `preview_main_table` + partial résultat

**Files:**
- Modify: `app/controllers/admin/schema_builder_controller.rb`
- Create: `app/views/admin/schema_builder/_preview_result.html.haml`
- Modify: `spec/controllers/admin/schema_builder_controller_spec.rb`

- [ ] **Step 1: Spec failing**

```ruby
describe 'POST #preview_main_table' do
  let(:demarche_descriptor) { double(:descriptor) }
  let(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: 'Dossiers') }

  before do
    allow_any_instance_of(Admin::SchemaBuilderController).to receive(:demarche_descriptor).and_return(demarche_descriptor)
    allow(SchemaBuilders::MainTableBuilder).to receive(:new).and_return(
      instance_double(SchemaBuilders::MainTableBuilder,
        preview: { table_name: 'Dossiers', fields: [{ name: 'Nom', type: 'text' }] }
      )
    )
  end

  it 'retourne un Turbo Stream avec le preview' do
    post :preview_main_table, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
    expect(response.body).to include('Nom')
    expect(response.body).to include('text')
  end
end
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implémenter**

```ruby
# Controller
def preview_main_table
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  builder = SchemaBuilders::MainTableBuilder.new(
    target: target_adapter_for(target),
    type_mapper: SchemaBuilders::TypeMapper.for(target.target_type.to_sym),
    field_filter: SchemaBuilders::FieldFilter.for(target.target_type.to_sym)
  )
  result = builder.preview(demarche_descriptor, application_id: target.application_external_id, table_name: target.main_table_external_id || default_main_table_name)

  render turbo_stream: turbo_stream.replace("main-table-#{target.id}", partial: 'main_table_section', locals: { target: target, preview: result })
end

private

def demarche_descriptor
  # Adapter : utiliser la classe existante qui charge le DemarcheDescriptor via GraphQL
  MesDemarches::DemarcheLoader.new(@demarche).load
end

def default_main_table_name
  "Dossiers démarche #{@demarche.id}"
end
```

Note : `MesDemarches::DemarcheLoader` est un placeholder — utiliser le vrai loader existant dans le projet (à identifier dans `app/lib/mes_demarches/` ou similaire).

- [ ] **Step 4: Partial `_preview_result`**

```haml
-# app/views/admin/schema_builder/_preview_result.html.haml
%div.mt-3
  %h6 Aperçu — #{preview[:table_name]}
  %table.table.table-sm
    %thead
      %tr
        %th Nom
        %th Type
    %tbody
      - preview[:fields].each do |field|
        %tr
          %td= field[:name]
          %td
            %code= field[:type]
```

Modifier `_main_table_section.html.haml` pour rendre `_preview_result` si `local_assigns[:preview]` est présent :

```haml
- if local_assigns[:preview]
  = render 'preview_result', preview: preview
- if local_assigns[:build_result]
  = render 'build_result', build_result: build_result
```

- [ ] **Step 5: PASS + Commit**

```bash
git add -A
git commit -m "feat(refonte): preview_main_table avec Turbo Stream"
git push
```

### Task F3 : Action `build_main_table` + partial résultat

**Files:**
- Modify: `app/controllers/admin/schema_builder_controller.rb`
- Create: `app/views/admin/schema_builder/_build_result.html.haml`

- [ ] **Step 1: Spec**

Similaire au preview mais teste que :
- `MainTableBuilder#build!` est appelé
- `target.last_synced_at` est mis à jour
- Le résultat (created/updated) est rendu

```ruby
it 'met à jour last_synced_at' do
  freeze_time = Time.zone.parse('2026-05-28 12:00')
  travel_to(freeze_time) do
    post :build_main_table, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
    expect(target.reload.last_synced_at).to be_within(1.second).of(freeze_time)
  end
end
```

- [ ] **Step 2: Implémenter**

```ruby
def build_main_table
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  builder = SchemaBuilders::MainTableBuilder.new(
    target: target_adapter_for(target),
    type_mapper: SchemaBuilders::TypeMapper.for(target.target_type.to_sym),
    field_filter: SchemaBuilders::FieldFilter.for(target.target_type.to_sym)
  )
  result = builder.build!(demarche_descriptor, application_id: target.application_external_id, table_name: target.main_table_external_id || default_main_table_name)

  target.update!(main_table_external_id: result[:table_id], last_synced_at: Time.current)

  render turbo_stream: turbo_stream.replace("main-table-#{target.id}", partial: 'main_table_section', locals: { target: target, build_result: result })
end
```

- [ ] **Step 3: Partial `_build_result`**

```haml
-# app/views/admin/schema_builder/_build_result.html.haml
%div.alert{class: build_result[:action] == :created ? 'alert-success' : 'alert-info'}
  - if build_result[:action] == :created
    Table créée (ID #{build_result[:table_id]})
  - else
    Table mise à jour (ID #{build_result[:table_id]})
```

- [ ] **Step 4: PASS + Commit**

```bash
git add -A
git commit -m "feat(refonte): build_main_table avec Turbo Stream + maj last_synced_at"
git push
```

### Task F4 : Stimulus `build_action_controller` (spinner)

**Files:**
- Create: `app/javascript/controllers/schema_builder/build_action_controller.js`

- [ ] **Step 1: Écrire**

```javascript
// app/javascript/controllers/schema_builder/build_action_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  start(event) {
    const btn = event.currentTarget
    btn.disabled = true
    btn.dataset.originalText = btn.textContent
    btn.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span>En cours…'
  }
}
```

- [ ] **Step 2: Brancher dans le partial**

Modifier `_main_table_section.html.haml` pour ajouter `data: { action: 'click->build-action#start' }` aux boutons.

- [ ] **Step 3: System test**

```ruby
it 'affiche un spinner pendant le build', :js do
  # stub MainTableBuilder pour bloquer 500ms
  click_button 'Build'
  expect(page).to have_selector('.spinner-border')
end
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(refonte): Stimulus build_action_controller (spinner)"
git push
```

---

## Phase G — Avis section (1.5 jour)

Pattern identique à Phase F mais pour la table Avis. Désactivé visuellement si target_type = 'grist'.

### Task G1 : Partial `_avis_section`

**Files:**
- Create: `app/views/admin/schema_builder/_avis_section.html.haml`

```haml
%turbo-frame{id: "avis-#{target.id}"}
  %div.card.mt-3
    %div.card-header
      %h5.mb-0
        Table Avis
        %span.badge.bg-secondary.ms-2= avis_status_label(target)
    %div.card-body
      - if target.target_type == 'grist'
        %p.text-muted{title: 'Non supporté par Grist pour l\'instant'}
          Fonctionnalité indisponible pour Grist
      - else
        = button_to 'Preview', preview_avis_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type), method: :post, class: 'btn btn-outline-primary me-2', data: { turbo_frame: "avis-#{target.id}" }
        = button_to 'Build', build_avis_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type), method: :post, class: 'btn btn-primary', data: { turbo_frame: "avis-#{target.id}", turbo_confirm: 'Créer/maj la table Avis ?' }

  - if local_assigns[:preview]
    = render 'preview_result', preview: preview
  - if local_assigns[:build_result]
    = render 'build_result', build_result: build_result
```

### Task G2 : Actions `preview_avis` + `build_avis` + spec

**Files:**
- Modify: `app/controllers/admin/schema_builder_controller.rb`

```ruby
def preview_avis
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  raise ActionController::BadRequest, 'Avis non supporté pour Grist' if target.target_type == 'grist'

  builder = SchemaBuilders::AvisBuilder.new(
    target: target_adapter_for(target),
    type_mapper: SchemaBuilders::TypeMapper.for(target.target_type.to_sym)
  )
  result = builder.preview(demarche_descriptor, application_id: target.application_external_id)
  render turbo_stream: turbo_stream.replace("avis-#{target.id}", partial: 'avis_section', locals: { target: target, preview: result })
end

def build_avis
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  raise ActionController::BadRequest if target.target_type == 'grist'

  builder = SchemaBuilders::AvisBuilder.new(
    target: target_adapter_for(target),
    type_mapper: SchemaBuilders::TypeMapper.for(target.target_type.to_sym)
  )
  result = builder.build!(demarche_descriptor, application_id: target.application_external_id)
  target.update!(avis_table_external_id: result[:table_id])
  render turbo_stream: turbo_stream.replace("avis-#{target.id}", partial: 'avis_section', locals: { target: target, build_result: result })
end
```

### Task G3 : Spec controller + helper avis_status

Mêmes patterns que F2-F3.

Commits :

```bash
git add -A && git commit -m "feat(refonte): section Avis (preview + build, Grist désactivé)"
git push
```

---

## Phase H — Blocks section (1.5 jour)

Pattern similaire mais collection de blocs. Chaque bloc a son propre statut de sync (via `SchemaBlockTarget`).

### Task H1 : Partial `_blocks_section`

**Files:**
- Create: `app/views/admin/schema_builder/_blocks_section.html.haml`

```haml
%turbo-frame{id: "blocks-#{target.id}"}
  %div.card.mt-3
    %div.card-header
      %h5.mb-0
        Blocs répétables
        - blocks_count = target.schema_block_targets.count
        - if blocks_count.positive?
          %span.badge.bg-secondary.ms-2= "#{blocks_count} blocs"
    %div.card-body
      %table.table.table-sm
        %thead
          %tr
            %th Bloc
            %th Statut
        %tbody
          - target.schema_block_targets.order(:block_descriptor_id).each do |block|
            %tr
              %td= block.block_descriptor_id
              %td= block_status_label(block)
      = button_to 'Preview tous', preview_blocks_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type), method: :post, class: 'btn btn-outline-primary me-2', data: { turbo_frame: "blocks-#{target.id}" }
      = button_to 'Build tous', build_blocks_admin_demarche_schema_path(demarche_demarche_id: target.demarche_id, target: target.target_type), method: :post, class: 'btn btn-primary', data: { turbo_frame: "blocks-#{target.id}", turbo_confirm: 'Créer/maj tous les blocs ?' }

  - if local_assigns[:preview]
    %div.mt-3
      %h6 Aperçu des blocs
      - preview.each do |block|
        %div.mb-3
          %strong= block[:table_name]
          = render 'preview_result', preview: block
  - if local_assigns[:build_result]
    %div.mt-3
      - build_result.each do |block|
        %div.mb-2
          %strong= block[:table_name]
          %span.badge.bg-success.ms-2= block[:action]
```

### Task H2 : Actions `preview_blocks` + `build_blocks`

Similaire à Avis mais itère sur les blocs et crée/met à jour des `SchemaBlockTarget`.

```ruby
def build_blocks
  target = @demarche.schema_targets.find_by!(target_type: params[:target])
  builder = SchemaBuilders::BlockBuilder.new(
    target: target_adapter_for(target),
    type_mapper: SchemaBuilders::TypeMapper.for(target.target_type.to_sym),
    field_filter: SchemaBuilders::FieldFilter.for(target.target_type.to_sym)
  )
  results = builder.build!(demarche_descriptor, application_id: target.application_external_id)

  results.each do |r|
    block = target.schema_block_targets.find_or_initialize_by(block_descriptor_id: r[:block_descriptor_id])
    block.update!(backend_table_id: r[:table_id], last_synced_at: Time.current)
  end

  render turbo_stream: turbo_stream.replace("blocks-#{target.id}", partial: 'blocks_section', locals: { target: target.reload, build_result: results })
end
```

Commits :

```bash
git add -A && git commit -m "feat(refonte): section Blocks (preview + build sur tous les blocs)"
git push
```

---

## Phase I — Backward compatibility (1 jour)

### Task I1 : Controller legacy + vue

**Files:**
- Create: `app/controllers/admin/schema_builder_legacy_controller.rb`
- Create: `app/views/admin/schema_builder_legacy/index.html.haml`

- [ ] **Step 1: Spec**

```ruby
# spec/controllers/admin/schema_builder_legacy_controller_spec.rb
require 'rails_helper'

RSpec.describe Admin::SchemaBuilderLegacyController, type: :controller do
  let(:user) { create(:user) }
  before { sign_in user }

  describe 'GET #index' do
    it 'rend la liste des démarches' do
      demarche = create(:demarche)
      get :index
      expect(response).to have_http_status(:ok)
      expect(assigns(:demarches)).to include(demarche)
    end

    it 'affiche un message d\'évolution' do
      get :index
      expect(response.body).to include('évolué')
    end
  end
end
```

- [ ] **Step 2: Implémenter**

```ruby
class Admin::SchemaBuilderLegacyController < ApplicationController
  before_action :authenticate_user!

  def index
    @demarches = Demarche.where(id: current_user.demarches.pluck(:id)).order(:libelle)
  end
end
```

```haml
-# app/views/admin/schema_builder_legacy/index.html.haml
%h1 Schéma de copie — interface évoluée

%div.alert.alert-info
  Cette interface a évolué. Sélectionnez une démarche pour accéder au nouveau dashboard.

%table.table
  %thead
    %tr
      %th Démarche
      %th Action
  %tbody
    - @demarches.each do |d|
      %tr
        %td= d.libelle
        %td= link_to 'Ouvrir', admin_demarche_schema_path(demarche_demarche_id: d.id), class: 'btn btn-sm btn-primary'
```

- [ ] **Step 3: PASS + Commit**

```bash
git add -A
git commit -m "feat(refonte): controller legacy avec liste des démarches"
git push
```

### Task I2 : Redirect des anciennes routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Ajouter les redirects**

```ruby
# config/routes.rb — REMPLACER les routes admin/baserow_schema et admin/grist_schema actuelles par :
get 'admin/baserow_schema',                 to: redirect('/admin/schema_builder_legacy')
get 'admin/baserow_schema/repetable_blocks', to: redirect('/admin/schema_builder_legacy')
get 'admin/grist_schema',                   to: redirect('/admin/schema_builder_legacy')
get 'admin/grist_schema/repetable_blocks',  to: redirect('/admin/schema_builder_legacy')
get 'admin/schema_builder_legacy',          to: 'admin/schema_builder_legacy#index'
```

ATTENTION : les anciens controllers `Admin::BaserowSchemaController` et `Admin::GristSchemaController` ne sont PAS encore supprimés (Phase K). Les routes ci-dessus écrasent les anciennes — si les autres actions POST (preview, build, etc.) étaient toujours utiles côté legacy, garder les routes POST. Mais le but étant de couper l'usage des anciennes, on les retire toutes en faveur de la redirection.

- [ ] **Step 2: Vérifier**

```bash
bin/rails routes | grep -E "baserow_schema|grist_schema"
```

Attendu : voir les redirects 301.

- [ ] **Step 3: Spec request**

```ruby
# spec/requests/legacy_redirects_spec.rb
require 'rails_helper'

RSpec.describe 'Legacy schema URLs', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it '/admin/baserow_schema redirige vers /admin/schema_builder_legacy' do
    get '/admin/baserow_schema'
    expect(response).to redirect_to('/admin/schema_builder_legacy')
  end

  it '/admin/grist_schema redirige vers /admin/schema_builder_legacy' do
    get '/admin/grist_schema'
    expect(response).to redirect_to('/admin/schema_builder_legacy')
  end
end
```

- [ ] **Step 4: PASS + Commit**

```bash
git add -A
git commit -m "feat(refonte): redirect des anciennes routes vers schema_builder_legacy"
git push
```

---

## Phase J — Migration de données (1 jour)

### Task J1 : Rake task `schema_targets:backfill`

**Files:**
- Create: `lib/tasks/schema_targets.rake`
- Create: `spec/lib/tasks/schema_targets_backfill_spec.rb`

- [ ] **Step 1: Spec**

```ruby
# spec/lib/tasks/schema_targets_backfill_spec.rb
require 'rails_helper'
require 'rake'

RSpec.describe 'schema_targets:backfill', type: :task do
  before(:all) do
    Rake.application.rake_require('tasks/schema_targets')
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task['schema_targets:backfill'] }
  after { task.reenable }

  it 'crée une SchemaTarget pour une démarche déjà sync dans Baserow' do
    demarche = create(:demarche)
    # Stub l'API Baserow pour qu'elle renvoie une table existante
    allow_any_instance_of(SchemaBuilders::BaserowTarget).to receive(:list_workspaces).and_return([{ 'id' => 42 }])
    allow_any_instance_of(SchemaBuilders::BaserowTarget).to receive(:list_applications).and_return([{ 'id' => 17 }])
    allow_any_instance_of(SchemaBuilders::BaserowTarget).to receive(:list_tables).and_return([
      { 'id' => 99, 'name' => "Dossiers démarche #{demarche.id}" }
    ])

    expect { task.invoke }.to change { SchemaTarget.count }.by(1)

    target = SchemaTarget.last
    expect(target.demarche).to eq(demarche)
    expect(target.target_type).to eq('baserow')
    expect(target.application_external_id).to eq('17')
    expect(target.main_table_external_id).to eq('99')
  end

  it 'est idempotent (rejouer ne duplique pas)' do
    demarche = create(:demarche)
    create(:schema_target, demarche: demarche, target_type: 'baserow')

    expect { task.invoke }.not_to change(SchemaTarget, :count)
  end
end
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implémenter**

```ruby
# lib/tasks/schema_targets.rake
namespace :schema_targets do
  desc 'Backfill SchemaTarget records for démarches already synchronized to Baserow/Grist'
  task backfill: :environment do
    %w[baserow grist].each do |target_type|
      adapter_class = target_type == 'baserow' ? SchemaBuilders::BaserowTarget : SchemaBuilders::GristTarget
      adapter = adapter_class.new

      Demarche.find_each do |demarche|
        next if demarche.schema_targets.exists?(target_type: target_type)

        workspace = locate_workspace(adapter, demarche)
        next unless workspace

        application = locate_application(adapter, workspace, demarche)
        next unless application

        main_table = locate_main_table(adapter, application, demarche)
        next unless main_table

        demarche.schema_targets.create!(
          target_type: target_type,
          workspace_external_id: workspace['id'].to_s,
          application_external_id: application['id'].to_s,
          main_table_external_id: main_table['id'].to_s
        )
        puts "[#{target_type}] backfilled démarche #{demarche.id}"
      end
    end
  end

  def locate_workspace(adapter, _demarche)
    adapter.list_workspaces.first
  end

  def locate_application(adapter, workspace, _demarche)
    adapter.list_applications(workspace['id']).first
  end

  def locate_main_table(adapter, application, demarche)
    expected_name = "Dossiers démarche #{demarche.id}"
    adapter.list_tables(application['id']).find { |t| t['name'] == expected_name }
  end
end
```

Note : l'heuristique de matching (`expected_name`) doit être ajustée à la convention de nommage réellement utilisée par l'ancien `MesDemarchesToBaserow::SchemaBuilder`. À vérifier au moment de l'exécution. Si plusieurs conventions ont coexisté, lister les candidats puis matcher.

- [ ] **Step 4: PASS + Commit**

```bash
git add -A
git commit -m "feat(refonte): rake task schema_targets:backfill (idempotent)"
git push
```

### Task J2 : Documentation backfill

**Files:**
- Modify: `docs/CONFIGURATION_GUIDE.md` (ou créer une note dans README)

- [ ] **Step 1: Documenter l'exécution**

Ajouter une section "Migration vers le nouveau dashboard de schéma" :

```markdown
## Migration vers le nouveau dashboard de schéma (slice 1)

Si la base contient déjà des démarches synchronisées vers Baserow ou Grist via l'ancienne
interface, exécuter :

\`\`\`bash
bundle exec rake schema_targets:backfill
\`\`\`

La tâche est idempotente. Les démarches non détectées dans les backends seront
reconfigurées par l'utilisateur au prochain accès au dashboard.
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
git add docs/
git commit -m "docs(refonte): instructions backfill SchemaTarget"
git push
```

---

## Phase K — Cleanup des anciens controllers/lib (0.5 jour)

À faire UNIQUEMENT après que tout le reste passe en QA et que le backfill a été exécuté.

### Task K1 : Suppression des anciens controllers

**Files:**
- Delete: `app/controllers/admin/baserow_schema_controller.rb`
- Delete: `app/controllers/admin/grist_schema_controller.rb`

- [ ] **Step 1: Supprimer**

```bash
git rm app/controllers/admin/baserow_schema_controller.rb
git rm app/controllers/admin/grist_schema_controller.rb
```

- [ ] **Step 2: Vérifier qu'aucune route n'y pointe plus**

```bash
bin/rails routes | grep -E "baserow_schema|grist_schema"
```

Attendu : que des redirects vers legacy, aucun pointage vers les anciens controllers.

- [ ] **Step 3: Lancer la suite de specs complète**

```bash
bundle exec rspec
```

Doit passer intégralement.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(refonte): suppression des anciens controllers Baserow/Grist Schema"
git push
```

### Task K2 : Suppression des anciennes vues

**Files:**
- Delete: `app/views/admin/baserow_schema/`
- Delete: `app/views/admin/grist_schema/`

```bash
git rm -r app/views/admin/baserow_schema/
git rm -r app/views/admin/grist_schema/
bundle exec rspec
git commit -m "refactor(refonte): suppression des anciennes vues HAML monolithiques"
git push
```

### Task K3 : Suppression des anciens namespaces lib

**Files:**
- Delete: `app/lib/mes_demarches_to_baserow/`
- Delete: `app/lib/mes_demarches_to_grist/`
- Modify: les éventuels callers (rechercher avec `grep`)

- [ ] **Step 1: Identifier les callers**

```bash
grep -r "MesDemarchesToBaserow\|MesDemarchesToGrist" app/ spec/ lib/ --include="*.rb" --include="*.rake"
```

- [ ] **Step 2: Migrer les callers restants vers `SchemaBuilders::*`**

Pour chaque caller trouvé, remplacer l'usage par l'équivalent `SchemaBuilders::*`. Les jobs de sync (`baserow_sync`, `grist_sync`) sont probablement à mettre à jour.

⚠️ **Si des jobs de sync planifiés utilisent encore les anciens namespaces**, NE PAS supprimer tout de suite. Migrer les jobs d'abord, dans un commit séparé.

- [ ] **Step 3: Supprimer**

```bash
git rm -r app/lib/mes_demarches_to_baserow/
git rm -r app/lib/mes_demarches_to_grist/
bundle exec rspec
git commit -m "refactor(refonte): suppression des anciens namespaces MesDemarchesToBaserow/Grist"
git push
```

### Task K4 : Suppression du smoke test transitoire

**Files:**
- Delete: `app/controllers/smoke_controller.rb`
- Modify: `config/routes.rb` (retirer la route `/__hotwire_smoke`)
- Delete: `spec/system/hotwire_smoke_spec.rb`

```bash
git rm app/controllers/smoke_controller.rb spec/system/hotwire_smoke_spec.rb
# éditer routes.rb pour retirer la ligne du smoke
git add config/routes.rb
git commit -m "chore(refonte): suppression du smoke test transitoire"
git push
```

---

## Checkpoint final du Slice 1

Avant de considérer le Slice 1 comme terminé :

- [ ] Toute la suite passe : `bundle exec rspec`
- [ ] Lint sans erreur : `bundle exec rake lint`
- [ ] Rubocop sans warning : `bundle exec rubocop`
- [ ] Le dashboard est accessible via `/admin/demarches/:id/schema` pour toute démarche existante
- [ ] L'ajout d'une cible Baserow ou Grist fonctionne via Turbo Stream
- [ ] La cascade workspace → app → table charge bien les données
- [ ] Preview et Build fonctionnent pour main_table, avis (Baserow only), blocks
- [ ] Les anciens controllers/vues/libs sont supprimés
- [ ] La rake task de backfill a été exécutée en staging et le résultat manuellement vérifié
- [ ] Le menu d'accès depuis l'interface vérif n'a PAS encore été modifié (c'est en Slice 2)
- [ ] PR ouverte de `feature/ui-refonte` vers `dev`, code review effectuée, merge

À l'issue du merge dans dev → planifier le Slice 2 (Vérification dossiers).

---

## Notes pour les phases ultérieures

**Slice 2 (à planifier séparément)** : polling Turbo Stream sur la vérif, extraction du query object, retrait du lien hardcodé vers Baserow et création du menu "Outils" dans le header (qui pointera vers le builder Slice 1 désormais en place).

**Slice 3 (à planifier séparément)** : suppression de `turbolinks`, `jquery-rails`, `coffee-rails`, `sprockets-rails` ; audit Devise ; finalisation import maps.

**Tooling JS final** : confirmé en Slice 3 que import maps est suffisant. Si en cours de Slice 1 on découvre un besoin de bundling (ex : minification du JS Stimulus pour la prod), repivot vers `jsbundling-rails` + bun à ce moment-là — décision révisable.
