# Refonte UI — Inspecteur Mes-Démarches

**Date** : 2026-05-28
**Auteur** : Christian Lautier (brainstorming avec Claude)
**Statut** : Design validé — en attente de plan d'implémentation

## Contexte

L'application Inspecteur Mes-Démarches expose deux interfaces fonctionnellement disjointes mais cohabitant dans un cadre UI commun :

1. **Vérification des dossiers** : affiche les erreurs détectées sur les dossiers soumis, montre les messages envoyés aux usagers, permet de re-déclencher la vérification.
2. **Builder de schéma Baserow / Grist** : construit le modèle de données dans Baserow (et Grist à terme) pour la copie automatique des dossiers.

### Problèmes identifiés (signalés utilisateur + cartographie code)

- Pas de partage d'info entre les deux types de builders (table principale vs blocs répétables/avis)
- Builder avis mélangé physiquement avec les blocs répétables (même page, IIFE de 529 lignes)
- Full page reload partout
- 60-83 % de JS vanilla inline dans 4 templates HAML monstrueux (300-670 lignes)
- HTML généré par concaténation de strings JS (180 lignes pour le preview)
- Duplication massive Baserow / Grist (2 namespaces parallèles, controllers copiés mot pour mot)
- Stack incohérente : Turbolinks + jQuery + Rails UJS + `data-turbo-method` (migration partielle)
- Zéro Stimulus, zéro Turbo Frames / Streams
- Aucun test controller, aucun modèle persistant côté builder

### Couplage entre les deux interfaces

Faible :
- Layout commun (`application.html.haml`)
- `ApplicationController` parent vide
- Un seul lien hardcodé dans `demarche/show.html.haml:9` vers le builder Baserow
- Pas de partials / helpers partagés
- JS global (`application.js`) chargé partout mais non utilisé par le builder

La séparation conceptuelle est donc techniquement facile à matérialiser.

## Objectifs de la refonte

1. **Découpler structurellement** les deux interfaces (chacune avec ses propres URL, vues, JS)
2. **Migrer vers Hotwire** (Turbo + Stimulus) pour éliminer les full reloads et le JS inline
3. **Consolider Baserow + Grist** derrière une abstraction pragmatique (2 cibles, pas de plugin architecture)
4. **Introduire la persistance** pour le builder : cible mémorisée par démarche
5. **Refondre l'UX du builder** en dashboard itératif (vs wizard one-shot)
6. **Préparer le futur** : multi-target par démarche (Baserow ET Grist simultanément), progress monitor de la vérification

## Approche retenue : verticales feature-first

Trois approches ont été évaluées (Big-Bang stack-first, Verticales feature-first, Modular Monolith). La verticale feature-first est retenue parce que :

- Le couplage entre les deux interfaces est déjà faible, donc le modular monolith est over-engineered
- Le big-bang retarde la valeur utilisateur de plusieurs semaines
- Chaque slice livre indépendamment

Durée totale estimée : **4-6 semaines**.

## Slice 1 — Builder Schema (3-4 semaines)

### 1.1 Routes et namespace

Toutes les routes du builder sont scopées à une démarche.

```
GET    /admin/demarches/:demarche_id/schema              → show (dashboard)
POST   /admin/demarches/:demarche_id/schema/targets      → ajouter une cible (baserow/grist)
DELETE /admin/demarches/:demarche_id/schema/targets/:type → retirer une cible
POST   /admin/demarches/:demarche_id/schema/:target/main_table/preview
POST   /admin/demarches/:demarche_id/schema/:target/main_table/build
POST   /admin/demarches/:demarche_id/schema/:target/avis/preview
POST   /admin/demarches/:demarche_id/schema/:target/avis/build
POST   /admin/demarches/:demarche_id/schema/:target/blocks/preview
POST   /admin/demarches/:demarche_id/schema/:target/blocks/build
```

Où `:target` ∈ `{baserow, grist}`.

Un seul controller : `Admin::SchemaBuilderController`. Les anciens `Admin::BaserowSchemaController` et `Admin::GristSchemaController` sont remplacés (redirects 302 vers les nouvelles routes pendant la phase de migration, suppression en Slice 3).

### 1.2 Modèle de données

Deux nouvelles tables ActiveRecord.

```ruby
# Table schema_targets
# Index unique sur (demarche_id, target_type) — un dossier peut être synchronisé
# vers Baserow ET Grist simultanément
create_table :schema_targets do |t|
  t.references :demarche, null: false, foreign_key: true
  t.string :target_type, null: false  # 'baserow' | 'grist'
  t.string :workspace_external_id
  t.string :application_external_id
  t.string :main_table_external_id
  t.string :avis_table_external_id
  t.datetime :last_synced_at
  t.timestamps
end
add_index :schema_targets, [:demarche_id, :target_type], unique: true

# Table schema_block_targets
# Une entrée par bloc répétable synchronisé
create_table :schema_block_targets do |t|
  t.references :schema_target, null: false, foreign_key: true
  t.string :block_descriptor_id, null: false  # ID du RepetitionChampDescriptor MD
  t.string :backend_table_id
  t.datetime :last_synced_at
  t.timestamps
end
add_index :schema_block_targets, [:schema_target_id, :block_descriptor_id], unique: true
```

Relations Rails :

```ruby
class Demarche < ApplicationRecord
  has_many :schema_targets, dependent: :destroy
end

class SchemaTarget < ApplicationRecord
  belongs_to :demarche
  has_many :schema_block_targets, dependent: :destroy
  enum target_type: { baserow: 'baserow', grist: 'grist' }
  validates :target_type, presence: true
  validates :demarche_id, uniqueness: { scope: :target_type }
end

class SchemaBlockTarget < ApplicationRecord
  belongs_to :schema_target
  validates :block_descriptor_id, uniqueness: { scope: :schema_target_id }
end
```

### 1.3 Abstraction backend (pragmatique)

Nouveau namespace `SchemaBuilders` qui consolide les deux namespaces actuels (`MesDemarchesToBaserow::*` et `MesDemarchesToGrist::*`).

```
app/lib/schema_builders/
├── target.rb              # Interface commune (module mixin)
├── baserow_target.rb      # Implémentation Baserow (wrappe StructureClient)
├── grist_target.rb        # Implémentation Grist
├── main_table_builder.rb  # Logique commune, prend un Target en paramètre
├── block_builder.rb       # Idem
├── avis_builder.rb        # Idem (Grist : NotImplementedError pour l'instant)
├── type_mapper.rb         # Mes-Démarches → types backend
└── field_filter.rb        # Filtrage des champs à inclure
```

Interface `Target` :

```ruby
module SchemaBuilders::Target
  def list_workspaces; end
  def list_applications(workspace_id); end
  def list_tables(application_id); end
  def create_table(application_id, name, fields); end
  def update_fields(table_id, fields); end
  def table_exists?(application_id, name); end
  def field_exists?(table_id, name); end
end
```

Les anciens fichiers (`app/lib/mes_demarches_to_baserow/*.rb`, `app/lib/mes_demarches_to_grist/*.rb`) sont supprimés en fin de Slice 1.

### 1.4 Dashboard UX (vue unique)

Une page par démarche, structure verticale, sections pliables.

```
┌──────────────────────────────────────────────────┐
│ Démarche #3194 — « Demande de subvention »      │
│                                                  │
│ Cibles actives :  [Baserow] [Grist] [+ Ajouter]  │
│ (onglets si plusieurs cibles, vue directe sinon) │
│                                                  │
│ Onglet Baserow sélectionné :                     │
│ Workspace : ____  App : ____  Table : ____       │
│                                                  │
│ ┌─ Table principale ──────────────────[▼]──┐    │
│ │ Statut : sync OK le 2026-05-15           │    │
│ │ [Preview] [Build]                         │    │
│ └────────────────────────────────────────────┘   │
│                                                  │
│ ┌─ Table Avis ────────────────────────[▼]──┐    │
│ │ Statut : jamais sync                      │    │
│ │ [Preview] [Build]                         │    │
│ └────────────────────────────────────────────┘   │
│                                                  │
│ ┌─ Blocs répétables (3) ───────────────[▼]──┐   │
│ │ • Membres du bureau    sync OK           │   │
│ │ • Pièces jointes        jamais sync      │   │
│ │ • Activités            erreur            │   │
│ │ [Preview tous] [Build tous]              │   │
│ └────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

**Ordre des sections** (validé utilisateur) : Table principale → Avis → Blocs répétables. Évite de scroller au-delà des blocs pour atteindre les avis.

**Cible Grist** : la section Avis est **désactivée visuellement** (grisée + tooltip "Non supporté par Grist") tant que l'`AvisBuilder` Grist n'est pas implémenté (cf. section 1.3, `NotImplementedError`). Pas de masquage complet pour signaler la fonctionnalité comme manquante, pas absente.

Chaque section = un **Turbo Frame** indépendant. Preview / Build retournent du **Turbo Stream** qui met à jour uniquement la section concernée.

Le HTML du preview est rendu **côté serveur** (partial Rails) au lieu de la concat JS actuelle.

### 1.5 Stimulus controllers

JS extrait des templates HAML vers des fichiers Stimulus dédiés.

```
app/javascript/controllers/schema_builder/
├── target_tabs_controller.js      # Switch entre Baserow / Grist
├── cascade_select_controller.js   # Workspace > App > Table (factorisé)
├── section_controller.js          # Pli / dépli + état d'une section
└── build_action_controller.js     # Bouton Preview/Build avec spinner inline
```

`cascade_select_controller.js` remplace les 4 implémentations dupliquées actuelles.

### 1.6 Vues HAML

```
app/views/admin/schema_builder/
├── show.html.haml                   # Dashboard squelette + onglets cibles
├── _target_tabs.html.haml           # Onglets Baserow / Grist
├── _target_panel.html.haml          # Panel d'une cible (workspace/app/table)
├── _main_table_section.html.haml    # Section Turbo Frame
├── _avis_section.html.haml          # Section Turbo Frame
├── _blocks_section.html.haml        # Section Turbo Frame
├── _preview_result.html.haml        # Rendu serveur du preview
└── _build_result.html.haml          # Rendu serveur du build
```

Chaque partial reste **sous 100 lignes**, sans bloc `:javascript` inline.

### 1.7 Backward compatibility et migration

**Anciennes URLs sans démarche_id** : les anciennes routes (`/admin/baserow_schema`, `/admin/grist_schema`, `/admin/baserow_schema/repetable_blocks`, etc.) ne portaient pas de démarche dans leur URL. On ne peut donc pas y faire un redirect 302 direct vers `/admin/demarches/:id/schema`.

Stratégie : pendant la durée du Slice 1, les anciennes routes pointent vers une **page intermédiaire** `/admin/schema_builder_legacy` qui :
- Affiche un message "Cette interface a évolué — sélectionnez une démarche pour accéder au nouveau dashboard"
- Liste les démarches accessibles à l'utilisateur connecté
- Chaque ligne pointe vers `/admin/demarches/:id/schema`

Cette page de transition est supprimée en Slice 3 avec les anciennes routes.

**Migration des données existantes** : un job de migration unique (rake task `schema_targets:backfill`) parcourt les démarches connues et :
1. Interroge l'API Baserow / Grist pour détecter si une table de schéma a déjà été créée (heuristique : recherche d'une table dont le nom matche la convention historique `demarche_<id>_main` ou similaire — à confirmer selon le code de `MesDemarchesToBaserow::SchemaBuilder` actuel)
2. Si détectée : crée un `SchemaTarget` avec les IDs externes correspondants
3. Si non détectée : skip (l'utilisateur reconfigurera au prochain accès)

Ce backfill est non-destructif (idempotent) et peut être relancé.

## Slice 2 — Vérification dossiers (1-2 semaines)

### 2.1 Vue de la situation actuelle

- `DemarcheController#show` charge tout en serveur (configurations, dossiers, checks, messages)
- Bouton "Vérifier" → full redirect, aucun retour live
- Bouton "Envoyer message" par ligne → full redirect
- Trois méthodes privées du controller font des requêtes ActiveRecord avec jointures (lignes 38-64)
- Lien hardcodé "Schéma Baserow" dans `show.html.haml:9`

### 2.2 Polling live avec Turbo Stream

- Clic "Vérifier" → POST `/demarche/verify` → renvoie un Turbo Stream qui remplace le bouton par un spinner et insère un Turbo Frame `verify_status` lazy-loaded
- Le frame `verify_status` utilise l'attribut `refresh` de Turbo 8 (`<turbo-frame id="verify_status" src="/demarche/verify_status" refresh="every">`) avec côté serveur un header `Refresh: 3` ou un meta-refresh **3 secondes** (validé utilisateur)
- Le frame affiche le statut courant (placeholder pour le futur progress monitor : "Vérification en cours — démarche X, dossier Y/Z")
- Quand `Sync.running?` redevient false, le serveur renvoie un frame "terminé" qui ne contient plus de directive de refresh — le polling s'arrête de lui-même
- Au moment où la vérification termine, le serveur push aussi un Turbo Stream (via `turbo_stream_from` sur le canal de la démarche) qui rafraîchit le tableau des dossiers

### 2.3 Action "Envoyer message" en Turbo Stream

PATCH `/demarche/post_message/:dossier` retourne désormais un Turbo Stream qui swap **uniquement** la ligne du dossier concerné. Plus de full reload.

### 2.4 Extraction du query object

Les trois méthodes privées du controller sortent vers :

```
app/queries/
└── dossiers_query.rb    # Encapsule filtrage par configuration + user
```

Le controller redevient mince.

### 2.5 Découplage UI vs builder

Le lien "Schéma Baserow" hardcodé dans `show.html.haml:9` disparaît. Il est remplacé par un menu déroulant **"Outils"** dans le header (`_header.html.haml`) :

- Outils
  - Schéma de copie (Baserow / Grist) → liste des démarches → dashboard scopé démarche

→ Suppression d'un couplage cross-feature identifié dans la cartographie.

### 2.6 Vues refactorées

`show.html.haml` (57 lignes inline aujourd'hui) découpé en partials :

```
app/views/demarche/
├── show.html.haml                  # Squelette + onglets
├── _verify_button.html.haml        # Bouton + frame status (Turbo)
├── _dossiers_table.html.haml       # Tableau dossiers
├── _dossier_row.html.haml          # Ligne individuelle (réutilisée par Turbo Stream)
└── _messages_subtable.html.haml    # Messages d'un dossier
```

### 2.7 Stack utilisée

Hotwire (Turbo + Stimulus) déjà introduit par Slice 1. Aucune nouvelle dépendance. Pas de Stimulus controller spécifique à la vérification (la feature est suffisamment simple pour rester en Turbo pur).

## Slice 3 — Cleanup transverse (3-5 jours)

### 3.1 Suppressions

- `turbolinks` → remplacé par Turbo
- `jquery3` → non utilisé après refonte
- `rails-ujs` → remplacé par `data-turbo-method`
- `coffee-script` + fichiers `.coffee` orphelins (notamment `diese.coffee` vide)
- Anciennes routes `/admin/baserow_schema/*` et `/admin/grist_schema/*` + leurs controllers
- Anciens namespaces `app/lib/mes_demarches_to_baserow/*.rb` et `app/lib/mes_demarches_to_grist/*.rb`
- Route morte `get 'demarche/report'` (déclarée sans action)

**Bootstrap 5 est conservé.** L'UI continue d'utiliser les composants Bootstrap natifs (card, accordion, badge, nav-tabs). Aucune refonte CSS / design system n'est planifiée.

### 3.2 Tooling JS

**Décision : import maps** (Rails 7 native, zéro build).

Justifications :
- Projet pas censé grandir
- Hotwire pensé pour import maps
- Pas de bundling = dev cycle plus rapide
- `bun` reste comme gestionnaire de package (linters / prettier éventuels), pas dans la chaîne de bundling runtime

Migration : `bin/rails javascript:install:importmap` puis import des deps (`@hotwired/turbo-rails`, `@hotwired/stimulus`) via `bin/importmap pin`.

### 3.3 Audit Devise

Vérifications :
- Version Devise dans `Gemfile.lock` vs dernière stable
- Onboarding : inscription, confirmation email, reset password, login fonctionnels
- `data: { 'turbo-method': :delete }` du logout compatible avec la version de Devise utilisée
- Console deprecation warnings
- Si bugs : maj Devise + ajustements helpers, dans un PR isolé

### 3.4 Layout et header

- Ajout du menu "Outils" (fait en Slice 2, à vérifier ici)
- Retrait `<%= javascript_include_tag 'application' %>` si passage à import maps
- Audit `application.bootstrap.scss` : retrait des imports orphelins

### 3.5 Ajouts CSS attendus

Estimation < 100 lignes SCSS additionnelles :
- Spinner inline pour boutons Preview / Build pendant l'exécution (~10 lignes)
- Style Turbo Frames "loading" (~10 lignes)
- Ajustements d'espacement dashboard (~20 lignes)

### 3.6 Documentation

- `README` : nouvelle stack, nouveau workflow builder
- `CLAUDE.md` : section "Stack" mise à jour (Hotwire, import maps, Bootstrap conservé)
- `docs/CONFIGURATION_GUIDE.md` : inchangé (config YAML non impactée)

## Testing

État actuel : zéro spec controller, specs lib partielles. La refonte est l'occasion d'introduire un socle minimal de non-régression.

### Slice 1

- `spec/controllers/admin/schema_builder_controller_spec.rb` — actions show/preview/build (happy path + 1 erreur par action)
- `spec/lib/schema_builders/*_spec.rb` — `MainTableBuilder` / `BlockBuilder` / `AvisBuilder` avec doubles pour `BaserowTarget` et `GristTarget`
- `spec/models/schema_target_spec.rb` — validations + unicité `(demarche_id, target_type)`
- `spec/models/schema_block_target_spec.rb`
- 1 spec système Capybara : dashboard happy path (changement de cible + preview + build via Turbo Stream)

### Slice 2

- `spec/controllers/demarche_controller_spec.rb` — show / verify / post_message
- `spec/queries/dossiers_query_spec.rb`
- 1 spec système : polling Turbo Stream pendant vérification

### Slice 3

- Tests d'intégration Devise (inscription, login, logout, reset password)

Objectif : **specs de non-régression sur les flux principaux**, pas 100 % de couverture.

## Risques et mitigations

| Risque | Mitigation |
|---|---|
| Coexistence Hotwire + Turbolinks/jQuery durant Slices 1-2 | Couplage faible entre les deux interfaces (mesuré dans la cartographie). Aucun JS partagé. Cohabitation tient. |
| Régression silencieuse sur le builder existant en prod pendant la refonte | Slice 1 ne supprime pas les anciennes routes (redirects 302) jusqu'au Slice 3. Rollback = git revert. |
| Démarches existantes sans `SchemaTarget` | Migration de données : pour chaque démarche déjà synchronisée (heuristique via API Baserow / Grist), créer un `SchemaTarget` avec les IDs externes. Sinon reconfiguration au prochain accès. |
| Devise update casse l'auth | Audit isolé en Slice 3, PR séparé si maj risquée. |
| Charge serveur du polling 3s | Polling actif uniquement si `Sync.running?` true. Sinon frame statique. Auto-arrêt côté serveur. |

## Hors scope (chantiers futurs)

1. **Progress monitor VerificationService complet** — le Slice 2 pose le hook UI (frame qui affichera "démarche X, dossier Y/Z") mais le backend renvoie pour l'instant juste "en cours". Le chantier futur enrichira `Sync` (ou nouvelle table) avec les compteurs détaillés, sans toucher au frontend.
2. **Interface de création de configuration YAML** — mentionné comme "ce serait cool", reporté.
3. **Tests système exhaustifs sur l'existant non touché**.
4. **Refonte des FieldCheckers / InspectorTasks** — logique métier inchangée.
5. **Migration Ruby/Rails majeure** — suit son propre calendrier.

## Décisions clés (récapitulatif)

| Décision | Valeur |
|---|---|
| Approche globale | Verticales feature-first (B) |
| Ordre des slices | Builder → Vérification → Cleanup |
| Stack JS cible | Hotwire (Turbo + Stimulus) + Bootstrap 5 + import maps |
| Backends supportés | Baserow + Grist, abstraction pragmatique (pas pluggable) |
| Multi-target par démarche | Oui (Baserow ET Grist simultanément possibles) |
| UX builder | Dashboard itératif (sections pliables) |
| Ordre sections dashboard | Table principale → Avis → Blocs |
| Persistance builder | Table `schema_targets` + `schema_block_targets` |
| Polling vérification | 3 secondes |
| Point d'entrée builder | Menu "Outils" dans header |
| Tests | Specs de non-régression sur flux principaux |
| Durée totale estimée | 4-6 semaines |
