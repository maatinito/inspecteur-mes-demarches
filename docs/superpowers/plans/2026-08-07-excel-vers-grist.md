# Plugin `excel_vers_grist` — Plan d'implémentation

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — utiliser `superpowers:subagent-driven-development` (recommandé) ou `superpowers:executing-plans` pour exécuter ce plan tâche par tâche. Les étapes utilisent la syntaxe case à cocher (`- [ ]`).

**Objectif :** rapatrier dans le robot la recopie des lignes d'un Excel joint vers une table Grist liée au dossier, aujourd'hui prototypée dans n8n, sous forme d'un plugin `excel_vers_grist` réutilisant l'existant.

**Architecture :** le cœur de lecture Excel est extrait de `Excel::GetSheets` vers un service pur `Excel::SheetReader` (fichier → feuilles → colonnes typées + lignes), consommé à la fois par `GetSheets` (modèle pipeline, inchangé pour ses appelants) et par le nouveau plugin `ExcelVersGrist` (FieldChecker, modèle « par dossier »). La synchro réutilise `MesDemarchesToGrist::RowUpserter` et `Grist::Client`. Un garde par empreinte (checksum du contenu, source Mes-Démarches) évite tout retraitement inutile.

**Tech stack :** Ruby on Rails, RSpec, `roo` (lecture xlsx), API REST Grist (`Grist::Client`), GraphQL Mes-Démarches.

**Spec de référence :** `docs/superpowers/specs/2026-06-19-excel-vers-grist-design.md` (design validé). Ce plan la suit, avec deux écarts explicitement motivés (§ « Écarts assumés »).

---

## Contraintes globales

- Ruby/Rails du projet, RSpec pour les tests. `bundle exec rspec` doit rester vert.
- **Avant chaque commit : `bundle exec rubocop -A` puis `bundle exec rake lint`** (règle projet non négociable).
- Aucun appel réseau dans les specs : `Grist::Client` est stubbé, les fichiers Excel sont des fixtures locales.
- Format xlsx uniquement (formats lus par `roo`). CSV hors périmètre.
- Les dates Grist s'écrivent en **epoch secondes** ; `ChoiceList` en `["L", …]` ; `Attachments` en `["L", id…]`.
- Type d'une colonne Grist existante : **jamais modifié** par le code. Un conflit est loggé, pas appliqué.
- Nommage et commentaires en français, cohérents avec `app/lib/mes_demarches_to_grist/`.
- Le plugin ne crée **pas** la table cible (créée à la main) ; il crée seulement des colonnes manquantes.
- Le YAML de configuration n'est pas versionné : déploiement via `deployment/robot-mes-demarches-{staging,production}` puis `mirror_*.sh`.

---

## Leçons capitalisées du workflow n8n « Pesticides to Grist : Substances »

Le workflow `BoS7lRfdrOYCcmdE` tourne en production depuis mars 2026 sur exactement ce cas d'usage. Son observation, plus le constat terrain du 07/08/2026 (« rien ne s'écrivait dans le numéro de dossier, il a fallu passer en mode liste »), donnent treize enseignements. Chacun est rattaché à la tâche qui le traite.

| # | Constat | Conséquence pour le plugin | Tâche |
|---|---|---|---|
| 1 | Écrire le **numéro Mes-Démarches** dans une colonne `Ref` ne produit **rien** : la cellule reste vide, sans erreur. Il faut l'encodage liste `["l", valeur]` qui fait résoudre la référence par la colonne visible. Vérifié : `Substances.Dossier` est `Ref:Dossiers` avec `visibleCol: 2`, et les valeurs stockées sont des **row ids Grist** (5, 6…), pas des numéros de dossier (617871). | **Tranche l'unique inconnue résiduelle de la spec (§8, point 2).** Un encodeur dédié est nécessaire, et l'écriture d'une clé `Ref` doit passer par lui. | 2 |
| 2 | Corollaire : filtrer une colonne `Ref` par le numéro de dossier ne matche jamais. `RowUpserter#find_record_id` et `SyncCoordinator#find_existing_record` utilisent `find_by(col, dossier_number)` — cassé dès que la colonne est un `Ref`. | Détecter le type de la colonne clé et filtrer par row id pour les `Ref`. | 2 |
| 3 | La colonne `excel_checksum` porte une **formule de valeur par défaut** (`isFormula: false`, `formula: '"-"'`) : toute ligne créée entre d'office dans l'état « à traiter ». | Reprendre le procédé pour la colonne d'empreinte : auto-créée avec défaut `"-"`, ce qui rend le rattrapage automatique sans code de migration. | 8 |
| 4 | L'écriture de l'empreinte est sur une branche **parallèle** à l'upsert, pas en aval : un upsert en échec marque quand même le fichier comme traité → lignes perdues **en silence**. | Confirme la décision spec §9 : n'écrire l'empreinte **qu'après** un upsert intégralement réussi. À encoder comme test explicite. | 8, 10 |
| 5 | L'upsert n8n est en `executeOnce` : un seul appel pour tout le lot, donc un échec emporte tous les dossiers du cycle. | Granularité **par dossier** (naturelle pour un FieldChecker), `continuer_si_erreur` par dossier. | 7, 10 |
| 6 | Pour un dossier à deux pièces jointes, l'empreinte est écrite deux fois (dernière gagne) — état non déterministe. | Confirme spec §6 : empreintes **triées puis concaténées en CSV**, une seule écriture. | 8 |
| 7 | L'extraction n8n est figée sur `Formulaire de saisie` / plage `B17:J213` : le fichier réel est un **formulaire à préambule de 16 lignes**. | La détection d'en-tête doit survivre à un préambule ; ce fichier entre au corpus de test comme cas de référence. | 3, 4 |
| 8 | Une étape normalise les unités (`kg`→`Kg`, `litre`/`l`→`L`) : la colonne cible est un `Choice`, qui rejette toute valeur hors liste. | Type par défaut `Text` (jamais de perte) ; sur colonne `Choice` existante, les valeurs non conformes sont **rapportées** dans la colonne d'erreurs au lieu d'être perdues. | 9, 11 |
| 9 | Le poids passe par un parsing tolérant (espaces retirés, virgule → point) : les cellules « numériques » des formulaires réels contiennent du **texte**. | **Contredit la spec §2** (« parsing de locale inutile ») : une coercition tolérante est indispensable. | 6 |
| 10 | Un filtre ne garde que les lignes dont deux colonnes précises sont non vides. | Règle de ligne vide + décompte des lignes ignorées rapporté. | 10, 11 |
| 11 | Un dédoublonnage sur 4 clés métier précède l'upsert (le même Excel contient des doublons). | Évité par construction : la clé d'upsert est `(Dossier, Ligne)` — l'index de ligne est unique, aucun dédoublonnage nécessaire. | 10 |
| 12 | n8n ne supprime jamais les lignes disparues de l'Excel : un fichier corrigé à la baisse laisse des substances fantômes. | Suppression des orphelins par `Ligne` au-delà du nombre de lignes courant. | 10 |
| 13 | n8n télécharge l'Excel **depuis Grist** (aller-retour) : le traitement dépend donc de la recopie préalable de la pièce jointe. | Le plugin lit le fichier **directement depuis Mes-Démarches** : une dépendance d'ordonnancement en moins, et il fonctionne même si la PJ n'est pas recopiée. | 7 |

Enseignement d'exploitation, hors code : le workflow a enchaîné 5 échecs `401 invalid API key` le 07/08 avant de repartir seul. `RowUpserter` a déjà un retry exponentiel sur 408/429/5xx — **401 n'y est pas** et ne doit pas y être ajouté (une clé invalide ne se répare pas en réessayant) ; `continuer_si_erreur` suffit à ne pas bloquer le reste.

## Écarts assumés par rapport à la spec

1. **`Excel::SheetReader` extrait plutôt que `GetSheets` étendu** (spec §4.1/§3.2). Motif : le plugin est un FieldChecker (`process(demarche, dossier)`) alors que `GetSheets` vit dans un modèle pipeline (`process_row(row, output)`) ; y brancher la lecture pour un tiers dénaturerait la classe. La spec note elle-même que `excel/get_sheets` n'est utilisé dans **aucune config déployée** — le refactor est donc sans risque, et `GetSheets` conserve son comportement en délégant.
2. **Coercition numérique tolérante conservée** (contre spec §2). Motif : leçon n°9 ci-dessus, constatée sur les fichiers réels de la 1536.

---

## Structure des fichiers

**À créer**
- `app/lib/excel/sheet_reader.rb` — lecture pure d'un xlsx : sélection de feuille, détection d'en-tête, sanitization des noms, inférence de types, coercition des valeurs. Aucune dépendance Grist ni Mes-Démarches.
- `app/lib/excel/column_descriptor.rb` — descripteur d'une colonne extraite : `nom` (sanitizé), `en_tete_brut`, `type_infere`, `index`.
- `app/lib/excel_vers_grist.rb` — le plugin (FieldChecker) : gating, garde par empreinte, mapping, création de colonnes, upsert, colonne d'erreurs.
- `app/lib/mes_demarches_to_grist/grist_ref.rb` — encodage/décodage des valeurs de colonnes `Ref` (la leçon n°1).
- `app/lib/mes_demarches_to_grist/ligne_upserter.rb` — upsert des lignes d'une table liée par `(Dossier, Ligne)` + suppression des orphelins.
- Specs miroirs sous `spec/lib/…`, fixtures sous `spec/fixtures/excel/`.

**À modifier**
- `app/lib/excel/get_sheets.rb` — délègue à `SheetReader`, gagne le paramètre `feuille`.
- `app/lib/mes_demarches_to_grist/row_upserter.rb:46,49,60-63` — encodage `Ref` de la clé, filtrage par row id.
- `app/lib/mes_demarches_to_grist/sync_coordinator.rb:259-265` — idem pour `find_existing_record`.
- `app/lib/grist/table.rb` — passe-plats `create_columns` / `update_column`.

---

## Phase 0 — Prérequis (chantier A de la spec)

### Task 1 : Filet de test sur `SyncCoordinator`

Spec §8 point 1. Le pipeline complet n'a aucun test : on le couvre avant d'y toucher.

**Fichiers :**
- Créer : `spec/lib/mes_demarches_to_grist/sync_coordinator_spec.rb`

**Interfaces :**
- Consomme : `MesDemarchesToGrist::SyncCoordinator.new(demarche_number, grist_config, options)`, `#sync_dossier(dossier)`.
- Produit : rien (tests seuls). Établit les doubles réutilisés par les tâches suivantes.

- [ ] **Étape 1 : écrire le test de câblage nominal**

```ruby
# spec/lib/mes_demarches_to_grist/sync_coordinator_spec.rb
require 'rails_helper'

RSpec.describe MesDemarchesToGrist::SyncCoordinator do
  let(:columns) do
    {
      'Dossier' => { id: 'Dossier', label: 'Dossier', type: 'Int', isFormula: false },
      'importateur' => { id: 'importateur', label: 'Importateur', type: 'Text', isFormula: false }
    }
  end
  let(:table) { instance_double(Grist::Table, columns: columns, client: instance_double(Grist::Client)) }
  let(:dossier) { double('dossier', number: 617_871, champs: [], annotations: [], demandeur: nil) }

  before do
    allow(Grist::Config).to receive(:table).and_return(table)
    allow(table).to receive(:find_by).with('Dossier', 617_871).and_return([])
    allow(table).to receive(:upsert_records)
  end

  it 'upserte la ligne principale avec la clé Dossier' do
    described_class.new(1536, { 'doc_id' => 'doc', 'table_id' => 'Dossiers' }, {}).sync_dossier(dossier)

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.first[:require]).to eq('Dossier' => 617_871)
    end
  end
end
```

- [ ] **Étape 2 : lancer le test pour le voir échouer ou révéler un bug de câblage**

Run : `bundle exec rspec spec/lib/mes_demarches_to_grist/sync_coordinator_spec.rb -v`
Attendu : échec (doubles incomplets) ou passage. **Tout échec révélant un vrai bug de câblage est à corriger dans `sync_coordinator.rb` avant de continuer** — c'est l'objet de la tâche.

- [ ] **Étape 3 : compléter les doubles jusqu'au vert, corriger les bugs révélés**

Ajuster les doubles (`SchemaBuilders::MetadataFields` a besoin d'un `demandeur` répondant à `__typename`) et corriger tout écart réel dans le coordinateur.

- [ ] **Étape 4 : ajouter le test « aucun changement → pas d'upsert »**

```ruby
  it "n'upserte pas quand rien n'a changé" do
    allow(table).to receive(:find_by).with('Dossier', 617_871)
      .and_return([{ 'id' => 3, 'fields' => { 'Dossier' => 617_871 } }])

    described_class.new(1536, { 'doc_id' => 'doc', 'table_id' => 'Dossiers' }, {}).sync_dossier(dossier)

    expect(table).not_to have_received(:upsert_records)
  end
```

- [ ] **Étape 5 : lancer la suite complète**

Run : `bundle exec rspec spec/lib/mes_demarches_to_grist/`
Attendu : tout vert.

- [ ] **Étape 6 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add spec/lib/mes_demarches_to_grist/sync_coordinator_spec.rb app/lib/mes_demarches_to_grist/
git commit -m "test(grist): couvrir le câblage de SyncCoordinator"
```

---

### Task 2 : Encodage des colonnes `Ref` — la leçon du terrain

Leçons n°1 et 2. Sans cette tâche, toute écriture dans une table liée dont la clé `Dossier` est un `Ref` est silencieusement perdue.

**Fichiers :**
- Créer : `app/lib/mes_demarches_to_grist/grist_ref.rb`
- Créer : `spec/lib/mes_demarches_to_grist/grist_ref_spec.rb`
- Modifier : `app/lib/mes_demarches_to_grist/row_upserter.rb:46,49,60-63`
- Modifier : `app/lib/mes_demarches_to_grist/sync_coordinator.rb:259-265`

**Interfaces :**
- Produit : `MesDemarchesToGrist::GristRef.encode_key(value, col_type)` → `["l", value]` si `col_type` commence par `Ref:`, sinon `value`. `GristRef.ref?(col_type)` → booléen. Utilisés par `RowUpserter` (Task 2) et `LigneUpserter` (Task 10).

- [ ] **Étape 1 : écrire le test qui échoue**

```ruby
# spec/lib/mes_demarches_to_grist/grist_ref_spec.rb
require 'rails_helper'

RSpec.describe MesDemarchesToGrist::GristRef do
  describe '.ref?' do
    it { expect(described_class.ref?('Ref:Dossiers')).to be true }
    it { expect(described_class.ref?('Int')).to be false }
    it { expect(described_class.ref?(nil)).to be false }
  end

  describe '.encode_key' do
    it 'encode une référence en recherche par colonne visible' do
      expect(described_class.encode_key(617_871, 'Ref:Dossiers')).to eq(['l', 617_871])
    end

    it 'laisse les autres types intacts' do
      expect(described_class.encode_key(617_871, 'Int')).to eq(617_871)
      expect(described_class.encode_key('abc', 'Text')).to eq('abc')
    end

    it 'ne double jamais un encodage déjà fait' do
      expect(described_class.encode_key(['l', 617_871], 'Ref:Dossiers')).to eq(['l', 617_871])
    end
  end
end
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/mes_demarches_to_grist/grist_ref_spec.rb`
Attendu : ÉCHEC — `uninitialized constant MesDemarchesToGrist::GristRef`.

- [ ] **Étape 3 : implémenter le minimum**

```ruby
# frozen_string_literal: true

module MesDemarchesToGrist
  # Encodage des valeurs destinées à une colonne Grist de type référence.
  #
  # Une colonne `Ref:Table` stocke le *row id* de la ligne visée. Y écrire une
  # valeur métier (le numéro de dossier Mes-Démarches) ne produit rien : Grist
  # n'échoue pas, la cellule reste vide — panne silencieuse constatée en
  # production sur la table Substances du doc pesticides.
  #
  # L'encodage `["l", valeur]` demande à Grist de *rechercher* la ligne dont la
  # colonne visible vaut `valeur`, et d'en stocker le row id. C'est la seule
  # forme robuste quand on ne connaît que la clé métier.
  module GristRef
    LOOKUP_MARKER = 'l'

    def self.ref?(col_type)
      col_type.to_s.start_with?('Ref:')
    end

    def self.encode_key(value, col_type)
      return value unless ref?(col_type)
      return value if value.is_a?(Array) && value.first == LOOKUP_MARKER

      [LOOKUP_MARKER, value]
    end
  end
end
```

- [ ] **Étape 4 : lancer pour vérifier le passage**

Run : `bundle exec rspec spec/lib/mes_demarches_to_grist/grist_ref_spec.rb`
Attendu : PASS.

- [ ] **Étape 5 : écrire le test d'intégration dans `RowUpserter`**

```ruby
# à ajouter dans spec/lib/mes_demarches_to_grist/row_upserter_spec.rb
context 'quand la colonne clé est une référence' do
  let(:field_metadata) { { 'Dossier' => { id: 'Dossier', label: 'Dossier', type: 'Ref:Dossiers' } } }
  let(:table) { instance_double(Grist::Table) }

  it 'envoie la clé en encodage de recherche' do
    allow(table).to receive(:upsert_records)
    allow(table).to receive(:find_by).and_return([{ 'id' => 7 }])

    described_class.new(table, {}, field_metadata).upsert_row(617_871, {})

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.first[:require]['Dossier']).to eq(['l', 617_871])
      expect(records.first[:fields]['Dossier']).to eq(['l', 617_871])
    end
  end

  it 'retrouve la ligne par row id et non par clé métier' do
    allow(table).to receive(:upsert_records)
    allow(table).to receive(:find_by).with('Dossier', ['l', 617_871]).and_return([{ 'id' => 7 }])

    expect(described_class.new(table, {}, field_metadata).upsert_row(617_871, {})).to eq(7)
  end
end
```

- [ ] **Étape 6 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/mes_demarches_to_grist/row_upserter_spec.rb`
Attendu : ÉCHEC — la clé partie est `617871` brut.

- [ ] **Étape 7 : brancher l'encodeur dans `RowUpserter`**

Dans `upsert_with_retry`, remplacer les lignes 45-49 :

```ruby
      # Assurer que la colonne Dossier est dans les données, encodée selon son type :
      # une colonne Ref exige la forme de recherche ["l", valeur] (cf. GristRef).
      key_type = @field_metadata.dig(@dossier_col_id, :type)
      key_value = GristRef.encode_key(dossier_number, key_type)
      data[@dossier_col_id] = key_value

      # Upsert natif Grist
      record = { require: { @dossier_col_id => key_value }, fields: data }
      @table.upsert_records([record])
```

et `find_record_id` :

```ruby
    def find_record_id(dossier_number)
      key_type = @field_metadata.dig(@dossier_col_id, :type)
      records = @table.find_by(@dossier_col_id, GristRef.encode_key(dossier_number, key_type))
      records.first&.dig('id')
    end
```

- [ ] **Étape 8 : lancer pour vérifier le passage**

Run : `bundle exec rspec spec/lib/mes_demarches_to_grist/`
Attendu : tout vert, y compris les tests existants (colonne `Int` inchangée).

- [ ] **Étape 9 : aligner `SyncCoordinator#find_existing_record`**

```ruby
    def find_existing_record(dossier_number)
      key_type = @main_field_metadata.dig(@dossier_col_id, :type)
      records = @main_table.find_by(@dossier_col_id, GristRef.encode_key(dossier_number, key_type))
      records.first
    rescue StandardError => e
      Rails.logger.error "GristSync: Erreur recherche record existant: #{e.message}"
      raise
    end
```

Ajouter le `require_relative 'mes_demarches_to_grist/grist_ref'` en tête de `app/lib/grist_sync.rb`, à la suite des autres.

- [ ] **Étape 10 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
bundle exec rspec spec/lib/mes_demarches_to_grist/ spec/lib/grist/
git add app/lib/mes_demarches_to_grist/ app/lib/grist_sync.rb spec/lib/mes_demarches_to_grist/
git commit -m "fix(grist): encoder les clés de colonnes Ref en recherche par colonne visible"
```

---

## Phase 1 — Extraction Excel

### Task 3 : `Excel::SheetReader` + sélection de feuille

**Fichiers :**
- Créer : `app/lib/excel/sheet_reader.rb`
- Créer : `spec/lib/excel/sheet_reader_spec.rb`
- Créer : fixtures `spec/fixtures/excel/simple.xlsx`, `spec/fixtures/excel/preambule.xlsx`, `spec/fixtures/excel/multi_feuilles.xlsx`
- Modifier : `app/lib/excel/get_sheets.rb`

**Interfaces :**
- Produit : `Excel::SheetReader.new(chemin, feuille: nil)`, `#colonnes` → `Array<Excel::ColumnDescriptor>`, `#lignes` → `Array<Hash>` (clés = noms sanitizés), `#nom_feuille` → String. `feuille` : `Integer` (position 1-based), `String` (nom), `nil` (1ʳᵉ feuille). Lève `Excel::SheetReader::FeuilleIntrouvable` si la feuille demandée n'existe pas.

- [ ] **Étape 1 : créer les fixtures**

```bash
mkdir -p spec/fixtures/excel
```

```ruby
# script jetable : bin/rails runner tmp/gen_fixtures.rb
require 'caxlsx'

Axlsx::Package.new do |p|
  p.workbook.add_worksheet(name: 'Feuille1') do |s|
    s.add_row %w[Nom Montant]
    s.add_row ['Dupont', 1200.5]
    s.add_row ['Martin', 300]
  end
  p.serialize('spec/fixtures/excel/simple.xlsx')
end

Axlsx::Package.new do |p|
  p.workbook.add_worksheet(name: 'Formulaire de saisie') do |s|
    3.times { s.add_row ['Direction de la biosécurité'] }   # préambule
    s.add_row []
    s.add_row ['Substances actives', 'Concentrations (%)', 'Poids/Volume total']
    s.add_row ['Géraniol', 12.5, '1 010,50']
    s.add_row ['Chlorure', 3, 110]
  end
  p.serialize('spec/fixtures/excel/preambule.xlsx')
end

Axlsx::Package.new do |p|
  p.workbook.add_worksheet(name: 'Garde') { |s| s.add_row ['rien'] }
  p.workbook.add_worksheet(name: 'Données') do |s|
    s.add_row %w[Code Libelle]
    s.add_row %w[A1 Alpha]
  end
  p.serialize('spec/fixtures/excel/multi_feuilles.xlsx')
end
```

Vérifier que `caxlsx` est disponible ; sinon générer les fixtures avec `roo`+`write_xlsx` ou les committer depuis un tableur.

- [ ] **Étape 2 : écrire le test qui échoue**

```ruby
# spec/lib/excel/sheet_reader_spec.rb
require 'rails_helper'

RSpec.describe Excel::SheetReader do
  let(:simple) { Rails.root.join('spec/fixtures/excel/simple.xlsx').to_s }
  let(:multi) { Rails.root.join('spec/fixtures/excel/multi_feuilles.xlsx').to_s }

  it 'lit la première feuille par défaut' do
    reader = described_class.new(simple)
    expect(reader.nom_feuille).to eq('Feuille1')
    expect(reader.colonnes.map(&:nom)).to eq(%w[Nom Montant])
    expect(reader.lignes).to eq([
      { 'Nom' => 'Dupont', 'Montant' => 1200.5 },
      { 'Nom' => 'Martin', 'Montant' => 300 }
    ])
  end

  it 'sélectionne une feuille par nom' do
    expect(described_class.new(multi, feuille: 'Données').lignes)
      .to eq([{ 'Code' => 'A1', 'Libelle' => 'Alpha' }])
  end

  it 'sélectionne une feuille par position 1-based' do
    expect(described_class.new(multi, feuille: 2).nom_feuille).to eq('Données')
  end

  it 'lève une erreur explicite sur feuille introuvable' do
    expect { described_class.new(multi, feuille: 'Absente') }
      .to raise_error(described_class::FeuilleIntrouvable, /Absente/)
  end

  it "traverse un préambule pour trouver la ligne d'en-tête" do
    reader = described_class.new(Rails.root.join('spec/fixtures/excel/preambule.xlsx').to_s)
    expect(reader.colonnes.map(&:nom)).to eq(['Substances actives', 'Concentrations', 'Poids/Volume total'])
    expect(reader.lignes.size).to eq(2)
  end
end
```

- [ ] **Étape 3 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/excel/sheet_reader_spec.rb`
Attendu : ÉCHEC — `uninitialized constant Excel::SheetReader`.

- [ ] **Étape 4 : implémenter `SheetReader` (lecture + sélection de feuille)**

```ruby
# frozen_string_literal: true

module Excel
  # Lecture d'un classeur xlsx, indépendante de Mes-Démarches et de Grist.
  #
  # Extrait de GetSheets pour être partageable avec le plugin ExcelVersGrist :
  # GetSheets vit dans un modèle pipeline (process_row/output) qui ne convient
  # pas à un FieldChecker « par dossier ».
  class SheetReader
    class FeuilleIntrouvable < StandardError; end

    def initialize(chemin, feuille: nil)
      @xlsx = Roo::Spreadsheet.open(chemin)
      @sheet = selectionner_feuille(feuille)
      @ligne_entete = detecter_ligne_entete(@sheet)
    end

    def nom_feuille
      @sheet.default_sheet
    end

    def colonnes
      @colonnes ||= construire_colonnes
    end

    def lignes
      @lignes ||= construire_lignes
    end

    def close
      @xlsx&.close
    end

    private

    def selectionner_feuille(feuille)
      noms = @xlsx.sheets
      nom = case feuille
            when nil then noms.first
            when Integer then noms[feuille - 1]
            else noms.find { |n| n == feuille }
            end
      raise FeuilleIntrouvable, "Feuille #{feuille.inspect} introuvable (disponibles : #{noms.join(', ')})" if nom.nil?

      @xlsx.sheet(nom)
    end

    # Reprise de la détection éprouvée de GetSheets : la ligne d'en-tête est
    # celle qui porte le plus de cellules remplies consécutives.
    def detecter_ligne_entete(sheet)
      ligne = 0
      max = 0
      sheet.each_row_streaming do |row|
        cell = row.find { |c| c.value.nil? } || row.last
        next if cell.nil?

        count = cell.coordinate[1]
        count -= 1 if cell.value.nil?
        if count > max
          max = count
          ligne = cell.coordinate[0]
        end
      end
      ligne
    end

    def entetes_bruts
      @entetes_bruts ||= @sheet.row(@ligne_entete)
    end

    def construire_colonnes
      entetes_bruts.each_with_index.map do |brut, index|
        ColumnDescriptor.new(nom: brut.to_s.strip, en_tete_brut: brut, index: index, type_infere: 'Text')
      end
    end

    def construire_lignes
      resultat = []
      @sheet.each_row_streaming do |row|
        next unless ligne_de_donnees?(row)

        resultat << colonnes.each_with_object({}) do |col, hash|
          hash[col.nom] = row[col.index]&.value
        end
      end
      resultat
    end

    def ligne_de_donnees?(row)
      return false if row.size < entetes_bruts.size
      return false unless row[1]

      row[1].coordinate[0] > @ligne_entete && row[1].value.present?
    end
  end
end
```

Et `app/lib/excel/column_descriptor.rb` :

```ruby
# frozen_string_literal: true

module Excel
  # Descripteur d'une colonne extraite d'une feuille.
  ColumnDescriptor = Struct.new(:nom, :en_tete_brut, :index, :type_infere, keyword_init: true)
end
```

- [ ] **Étape 5 : lancer les tests**

Run : `bundle exec rspec spec/lib/excel/sheet_reader_spec.rb`
Attendu : PASS sauf le test de préambule sur la sanitization (`Concentrations (%)` → `Concentrations`), traité en Task 4. Marquer ce test `pending` avec le commentaire « sanitization : Task 4 » si nécessaire pour garder la suite verte.

- [ ] **Étape 6 : faire déléguer `GetSheets` et lui donner `feuille`**

```ruby
    def authorized_fields
      super + %i[feuille]
    end

    def process_row(row, output)
      champs = object_field_values(row, params[:champ])
      champs.each do |champ_source|
        raise "Le champ #{params[:champ]} n'est pas de type PieceJustificative" if champ_source.__typename != 'PieceJustificativeChamp'

        source_file = champ_source.files.filter { File.extname(it.filename) == '.xlsx' }.last
        next unless source_file

        PieceJustificativeCache.get(source_file) do |file|
          reader = Excel::SheetReader.new(file, feuille: params[:feuille])
          output["#{params[:champ]}.#{reader.nom_feuille}"] = reader.lignes
        ensure
          reader&.close
        end
      end
      output
    end
```

Note : le comportement change — `GetSheets` exposait **toutes** les feuilles, il n'en expose plus qu'une (défaut : la 1ʳᵉ), conformément à la décision spec §11.1. Sans risque : `excel/get_sheets` n'apparaît dans aucune config déployée (vérifié dans la spec §4.1), seul `spec/factories/publipostage_v2.rb:48` le référence.

- [ ] **Étape 7 : lancer la suite Excel complète**

Run : `bundle exec rspec spec/lib/excel/ spec/lib/publipostage_v2_spec.rb`
Attendu : tout vert.

- [ ] **Étape 8 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add app/lib/excel/ spec/lib/excel/ spec/fixtures/excel/
git commit -m "feat(excel): extraire SheetReader et permettre la sélection de feuille"
```

---

### Task 4 : Sanitization des noms de colonnes

**Fichiers :**
- Modifier : `app/lib/excel/sheet_reader.rb`
- Modifier : `spec/lib/excel/sheet_reader_spec.rb`

**Interfaces :**
- Produit : `ColumnDescriptor#nom` sanitizé, `#en_tete_brut` conservé. Règles : ponctuation et retours-ligne retirés, `trim`, espaces multiples réduits ; doublons suffixés `_2`, `_3` ; en-tête vide sur colonne remplie → `Colonne_<index+1>`.

- [ ] **Étape 1 : écrire les tests qui échouent**

```ruby
  describe 'sanitization des noms' do
    def noms(entetes)
      reader = described_class.allocate
      reader.send(:sanitize_noms, entetes)
    end

    it 'retire la ponctuation et réduit les espaces' do
      expect(noms(["Concentrations (%)", "  Poids/Volume  total \n"]))
        .to eq(['Concentrations', 'Poids Volume total'])
    end

    it 'suffixe les doublons' do
      expect(noms(%w[Nom Nom Nom])).to eq(%w[Nom Nom_2 Nom_3])
    end

    it 'nomme les en-têtes vides par leur position' do
      expect(noms(['Nom', nil, ''])).to eq(['Nom', 'Colonne_2', 'Colonne_3'])
    end
  end
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/excel/sheet_reader_spec.rb -e sanitization`
Attendu : ÉCHEC — `undefined method 'sanitize_noms'`.

- [ ] **Étape 3 : implémenter**

```ruby
    PONCTUATION = %r{[(){}\[\]/\\,;:!?"'*%#&@|<>=+~^$`.]}

    # Grist tolère les espaces dans les libellés : on ne translittère pas, on
    # nettoie. Les doublons et les en-têtes vides doivent produire des noms
    # stables et distincts, sinon deux colonnes source écrasent la même cible.
    def sanitize_noms(entetes)
      vus = Hash.new(0)
      entetes.each_with_index.map do |brut, index|
        base = brut.to_s.gsub(/[\r\n]+/, ' ').gsub(PONCTUATION, ' ').squeeze(' ').strip
        base = "Colonne_#{index + 1}" if base.empty?
        vus[base] += 1
        vus[base] > 1 ? "#{base}_#{vus[base]}" : base
      end
    end
```

et brancher dans `construire_colonnes` :

```ruby
    def construire_colonnes
      noms = sanitize_noms(entetes_bruts)
      entetes_bruts.each_with_index.map do |brut, index|
        ColumnDescriptor.new(nom: noms[index], en_tete_brut: brut, index: index, type_infere: 'Text')
      end
    end
```

- [ ] **Étape 4 : lancer les tests, y compris le test de préambule précédemment `pending`**

Run : `bundle exec rspec spec/lib/excel/sheet_reader_spec.rb`
Attendu : PASS (retirer le `pending` de Task 3, étape 5).

- [ ] **Étape 5 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add app/lib/excel/sheet_reader.rb spec/lib/excel/sheet_reader_spec.rb
git commit -m "feat(excel): sanitizer les noms de colonnes (doublons, en-têtes vides)"
```

---

### Task 5 : Inférence de types

**Fichiers :**
- Modifier : `app/lib/excel/sheet_reader.rb`
- Modifier : `spec/lib/excel/sheet_reader_spec.rb`

**Interfaces :**
- Produit : `ColumnDescriptor#type_infere` ∈ `%w[Numeric Int Date DateTime Bool Text]`. Règle : type homogène sur les valeurs non nulles → ce type ; mixte ou colonne vide → `Text` (jamais de perte).

- [ ] **Étape 1 : écrire les tests qui échouent**

```ruby
  describe 'inférence de type' do
    def type(valeurs)
      described_class.allocate.send(:inferer_type, valeurs)
    end

    it { expect(type([1.5, 2.0])).to eq('Numeric') }
    it { expect(type([1, 2])).to eq('Int') }
    it { expect(type([Date.new(2026, 1, 1)])).to eq('Date') }
    it { expect(type([DateTime.new(2026, 1, 1, 8, 0)])).to eq('DateTime') }
    it { expect(type([true, false])).to eq('Bool') }
    it { expect(type(['a', 1])).to eq('Text') }
    it { expect(type([])).to eq('Text') }
    it { expect(type([nil, nil])).to eq('Text') }
    it 'ignore les nil pour juger de l’homogénéité' do
      expect(type([nil, 3, nil])).to eq('Int')
    end
  end
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/excel/sheet_reader_spec.rb -e "inférence"`
Attendu : ÉCHEC — `undefined method 'inferer_type'`.

- [ ] **Étape 3 : implémenter**

```ruby
    # DateTime avant Date : DateTime hérite de Date en Ruby.
    CLASSES_TYPES = [
      [TrueClass, 'Bool'], [FalseClass, 'Bool'],
      [Float, 'Numeric'], [Integer, 'Int'],
      [DateTime, 'DateTime'], [Time, 'DateTime'], [Date, 'Date']
    ].freeze

    def inferer_type(valeurs)
      types = valeurs.reject(&:nil?).map { |v| type_de(v) }.uniq
      return 'Text' if types.size != 1

      types.first
    end

    def type_de(valeur)
      CLASSES_TYPES.each { |klass, type| return type if valeur.is_a?(klass) }
      'Text'
    end
```

et enrichir `construire_colonnes` une fois les lignes connues :

```ruby
    def construire_colonnes
      noms = sanitize_noms(entetes_bruts)
      entetes_bruts.each_with_index.map do |brut, index|
        valeurs = valeurs_brutes_colonne(index)
        ColumnDescriptor.new(nom: noms[index], en_tete_brut: brut, index: index,
                             type_infere: inferer_type(valeurs))
      end
    end

    def valeurs_brutes_colonne(index)
      @valeurs_par_index ||= begin
        acc = Hash.new { |h, k| h[k] = [] }
        @sheet.each_row_streaming do |row|
          next unless ligne_de_donnees?(row)

          entetes_bruts.each_index { |i| acc[i] << row[i]&.value }
        end
        acc
      end
      @valeurs_par_index[index]
    end
```

Attention à l'ordre d'initialisation : `colonnes` dépend désormais d'un balayage des lignes. Vérifier qu'aucune récursion n'est introduite (`ligne_de_donnees?` n'appelle pas `colonnes`).

- [ ] **Étape 4 : lancer les tests**

Run : `bundle exec rspec spec/lib/excel/sheet_reader_spec.rb`
Attendu : tout vert.

- [ ] **Étape 5 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add app/lib/excel/ spec/lib/excel/
git commit -m "feat(excel): inférer le type Grist des colonnes extraites"
```

---

### Task 6 : Coercition tolérante des valeurs numériques

Leçon n°9. Les formulaires réels stockent `1 010,50` en **texte** dans des colonnes numériques.

**Fichiers :**
- Modifier : `app/lib/excel/sheet_reader.rb`
- Modifier : `spec/lib/excel/sheet_reader_spec.rb`

**Interfaces :**
- Produit : `SheetReader#lignes` renvoie des valeurs coercées quand la colonne cible est numérique. `SheetReader.coercer(valeur, type)` → valeur typée ou `nil` si impossible.

- [ ] **Étape 1 : écrire les tests qui échouent**

```ruby
  describe '.coercer' do
    it 'accepte les nombres déjà typés' do
      expect(described_class.coercer(1200.5, 'Numeric')).to eq(1200.5)
    end

    it 'tolère espaces, espaces insécables et virgule décimale' do
      expect(described_class.coercer("1 010,50", 'Numeric')).to eq(1010.5)
      expect(described_class.coercer("1 010.50", 'Numeric')).to eq(1010.5)
    end

    it 'renvoie nil sur texte non numérique' do
      expect(described_class.coercer('néant', 'Numeric')).to be_nil
    end

    it 'laisse le texte intact pour une colonne Text' do
      expect(described_class.coercer("1 010,50", 'Text')).to eq("1 010,50")
    end
  end
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/excel/sheet_reader_spec.rb -e coercer`
Attendu : ÉCHEC — méthode absente.

- [ ] **Étape 3 : implémenter**

```ruby
    # Les colonnes « numériques » des formulaires réels contiennent souvent du
    # texte saisi à la main (« 1 010,50 »). roo renvoie alors une String : on
    # coerce plutôt que de perdre la valeur. Constaté sur la démarche 1536.
    def self.coercer(valeur, type)
      return valeur unless %w[Numeric Int].include?(type)
      return valeur if valeur.is_a?(Numeric)
      return nil if valeur.nil?

      nettoye = valeur.to_s.gsub(/[\s ]/, '').tr(',', '.')
      return nil if nettoye.empty?

      nombre = Float(nettoye, exception: false)
      return nil if nombre.nil?

      type == 'Int' ? nombre.to_i : nombre
    end
```

et appliquer dans `construire_lignes` :

```ruby
        resultat << colonnes.each_with_object({}) do |col, hash|
          hash[col.nom] = self.class.coercer(row[col.index]&.value, col.type_infere)
        end
```

Note : une colonne dont les valeurs sont du texte numérique est inférée `Text` (mixte/texte) — la coercition n'agit donc que si le mapping YAML force `type: numeric` (Task 9) ou si la colonne Grist existante est numérique. C'est volontaire : on ne devine pas.

- [ ] **Étape 4 : lancer les tests**

Run : `bundle exec rspec spec/lib/excel/`
Attendu : tout vert.

- [ ] **Étape 5 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add app/lib/excel/ spec/lib/excel/
git commit -m "feat(excel): coercition tolérante des valeurs numériques saisies en texte"
```

---

## Phase 2 — Le plugin

### Task 7 : Squelette `ExcelVersGrist`

**Fichiers :**
- Créer : `app/lib/excel_vers_grist.rb`
- Créer : `spec/lib/excel_vers_grist_spec.rb`

**Interfaces :**
- Consomme : `Excel::SheetReader` (Tasks 3-6), `Grist::Config.table`.
- Produit : `ExcelVersGrist < FieldChecker`, `required_fields` = `%i[champ grist]`, `authorized_fields` = `%i[etat_du_dossier feuille colonnes options]`. `#process(demarche, dossier)`.

- [ ] **Étape 1 : écrire les tests de validation qui échouent**

```ruby
# spec/lib/excel_vers_grist_spec.rb
require 'rails_helper'

RSpec.describe ExcelVersGrist do
  let(:params_valides) do
    { champ: 'Excel avec avis', grist: { 'doc_id' => 'doc', 'table_id' => 'Substances' } }
  end

  it 'accepte une configuration complète' do
    plugin = described_class.new(params_valides)
    expect(plugin.valid?).to be true
    expect(plugin.errors).to be_empty
  end

  it 'exige doc_id et table_id' do
    plugin = described_class.new(champ: 'X', grist: { 'doc_id' => 'doc' })
    expect(plugin.valid?).to be false
    expect(plugin.errors.join).to match(/table_id/)
  end

  it 'exige le champ source' do
    expect(described_class.new(grist: params_valides[:grist]).valid?).to be false
  end

  it 'refuse un champ qui n’est pas une pièce justificative' do
    plugin = described_class.new(params_valides)
    champ = double('champ', __typename: 'TextChamp', label: 'Excel avec avis')
    dossier = double('dossier', number: 1, champs: [champ], annotations: [])
    expect { plugin.process(double(id: 1536), dossier) }.not_to raise_error
  end
end
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/excel_vers_grist_spec.rb`
Attendu : ÉCHEC — `uninitialized constant ExcelVersGrist`.

- [ ] **Étape 3 : implémenter le squelette**

```ruby
# frozen_string_literal: true

require_relative 'mes_demarches_to_grist/grist_ref'
require_relative 'mes_demarches_to_grist/ligne_upserter'

# Recopie les lignes d'un Excel joint au dossier vers une table Grist liée.
#
# Pendant « source Excel » de la synchro des blocs répétables : même cible
# (table liée à la table dossier), même clé d'upsert (Dossier, Ligne), mais les
# lignes viennent d'un fichier au lieu d'un bloc natif.
#
# Configuration YAML : cf. docs/superpowers/specs/2026-06-19-excel-vers-grist-design.md §5
class ExcelVersGrist < FieldChecker
  def version
    super + 1
  end

  def required_fields
    super + %i[champ grist]
  end

  def authorized_fields
    super + %i[feuille colonnes options]
  end

  def initialize(*args)
    super

    @errors << "Configuration 'grist.doc_id' manquante sur excel_vers_grist" unless @params[:grist]&.[]('doc_id')
    @errors << "Configuration 'grist.table_id' manquante sur excel_vers_grist" unless @params[:grist]&.[]('table_id')
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    champ = champ_source(dossier)
    return Rails.logger.info("ExcelVersGrist: champ #{@params[:champ]} absent ou vide (dossier #{dossier.number})") if champ.nil?

    fichiers = fichiers_xlsx(champ)
    return Rails.logger.info("ExcelVersGrist: aucun .xlsx sur #{@params[:champ]} (dossier #{dossier.number})") if fichiers.empty?

    traiter(demarche, dossier, fichiers)
  rescue StandardError => e
    Rails.logger.error "ExcelVersGrist: Erreur dossier #{dossier.number}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    Sentry.capture_exception(e, extra: { dossier: dossier.number, demarche: demarche.id })

    raise unless @params.dig(:options, 'continuer_si_erreur') == true
  end

  private

  def champ_source(dossier)
    (dossier.champs.to_a + dossier.annotations.to_a).find do |c|
      c.label == @params[:champ] && c.__typename == 'PieceJustificativeChamp'
    end
  end

  def fichiers_xlsx(champ)
    champ.files.to_a.select { |f| File.extname(f.filename.to_s).casecmp('.xlsx').zero? }
  end

  # Complété en Task 8 (garde d'empreinte), 9 (mapping/colonnes), 10 (upsert).
  def traiter(_demarche, _dossier, _fichiers)
    nil
  end
end
```

- [ ] **Étape 4 : lancer les tests**

Run : `bundle exec rspec spec/lib/excel_vers_grist_spec.rb`
Attendu : PASS.

- [ ] **Étape 5 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add app/lib/excel_vers_grist.rb spec/lib/excel_vers_grist_spec.rb
git commit -m "feat(grist): squelette du plugin excel_vers_grist"
```

---

### Task 8 : Garde par empreinte du contenu

Leçons n°3, 4 et 6. L'empreinte vient de la **source** (`checksum` MD5 exposé par GraphQL, déjà dans le fragment `ChampInfo` — `app/lib/mes_demarches.rb:166,173`), est stockée sur la **ligne principale**, et n'est écrite **qu'après** succès complet.

**Fichiers :**
- Modifier : `app/lib/excel_vers_grist.rb`
- Modifier : `spec/lib/excel_vers_grist_spec.rb`

**Interfaces :**
- Produit : `#empreinte_source(fichiers)` → String (checksums triés, joints par `,`), `#colonne_empreinte` → String (défaut `excel_checksum`), `#ensure_colonne_empreinte(table)` → crée la colonne Text avec valeur par défaut `"-"` si absente.

- [ ] **Étape 1 : écrire les tests qui échouent**

```ruby
  describe 'garde par empreinte' do
    let(:plugin) { described_class.new(params_valides) }

    it 'concatène les checksums triés (insensible à l’ordre des fichiers)' do
      a = double(filename: 'a.xlsx', checksum: 'zzz')
      b = double(filename: 'b.xlsx', checksum: 'aaa')
      expect(plugin.send(:empreinte_source, [a, b])).to eq('aaa,zzz')
      expect(plugin.send(:empreinte_source, [b, a])).to eq('aaa,zzz')
    end

    it 'saute le traitement quand l’empreinte est inchangée' do
      expect(plugin.send(:a_jour?, 'aaa,zzz', { 'fields' => { 'excel_checksum' => 'aaa,zzz' } })).to be true
    end

    it 'retraite quand l’empreinte diffère, ou vaut le sentinel' do
      expect(plugin.send(:a_jour?, 'aaa', { 'fields' => { 'excel_checksum' => '-' } })).to be false
      expect(plugin.send(:a_jour?, 'aaa', nil)).to be false
    end
  end
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/excel_vers_grist_spec.rb -e empreinte`
Attendu : ÉCHEC — méthodes absentes.

- [ ] **Étape 3 : implémenter**

```ruby
  SENTINEL_A_TRAITER = '-'
  COLONNE_EMPREINTE_DEFAUT = 'excel_checksum'

  def colonne_empreinte
    @params.dig(:options, 'colonne_empreinte') || COLONNE_EMPREINTE_DEFAUT
  end

  # Un PieceJustificative peut porter plusieurs fichiers : on trie les
  # empreintes avant de les concaténer, pour être insensible à l'ordre de
  # remontée GraphQL. Une seule écriture, contrairement au workflow n8n qui
  # écrivait une empreinte par fichier (dernière gagnante).
  def empreinte_source(fichiers)
    fichiers.map { |f| f.checksum.to_s }.sort.join(',')
  end

  def a_jour?(empreinte, ligne_principale)
    return false if ligne_principale.nil?

    stockee = ligne_principale.dig('fields', colonne_empreinte)
    stockee.present? && stockee != SENTINEL_A_TRAITER && stockee == empreinte
  end

  # Colonne technique : créée avec la valeur par défaut "-" (formule de défaut
  # Grist, isFormula=false). Toute ligne créée ensuite entre d'office dans
  # l'état « à traiter » — procédé repris du doc pesticides.
  def ensure_colonne_empreinte(table)
    return if table.columns.key?(colonne_empreinte)

    table.create_columns([{
      id: colonne_empreinte,
      fields: { label: 'Excel checksum', type: 'Text', isFormula: false, formula: %("#{SENTINEL_A_TRAITER}") }
    }])
    Rails.logger.info "ExcelVersGrist: colonne #{colonne_empreinte} créée (défaut #{SENTINEL_A_TRAITER.inspect})"
  end
```

- [ ] **Étape 4 : lancer les tests**

Run : `bundle exec rspec spec/lib/excel_vers_grist_spec.rb`
Attendu : PASS.

- [ ] **Étape 5 : ajouter les passe-plats manquants à `Grist::Table`**

```ruby
    # app/lib/grist/table.rb
    def create_columns(data)
      client.create_columns(doc_id, table_id, data)
    end

    def update_column(col_id, fields)
      client.update_column(doc_id, table_id, col_id, fields)
    end
```

Puis un test dans `spec/lib/grist/table_spec.rb` vérifiant la délégation :

```ruby
  it 'délègue la création de colonnes au client' do
    client = instance_double(Grist::Client)
    allow(client).to receive(:create_columns)
    described_class.new(client, 'doc', 'T').create_columns([{ id: 'X' }])
    expect(client).to have_received(:create_columns).with('doc', 'T', [{ id: 'X' }])
  end
```

- [ ] **Étape 6 : lancer les tests Grist**

Run : `bundle exec rspec spec/lib/grist/ spec/lib/excel_vers_grist_spec.rb`
Attendu : tout vert.

- [ ] **Étape 7 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add app/lib/excel_vers_grist.rb app/lib/grist/table.rb spec/lib/
git commit -m "feat(grist): garde par empreinte du contenu Excel avec sentinel de retraitement"
```

---

### Task 9 : Mapping des colonnes et création des colonnes manquantes

**Fichiers :**
- Modifier : `app/lib/excel_vers_grist.rb`
- Modifier : `spec/lib/excel_vers_grist_spec.rb`

**Interfaces :**
- Produit : `#mapping(colonnes)` → `Hash{nom_source => {cible:, type:}}`, `#ensure_colonnes(table, colonnes)` → crée les colonnes cibles absentes (sauf si `creer_colonnes_manquantes: false`), renvoie la liste des noms créés. Ne modifie **jamais** le type d'une colonne existante ; un conflit est loggé.

- [ ] **Étape 1 : écrire les tests qui échouent**

```ruby
  describe 'mapping' do
    it 'sans configuration : cible = source, type inféré' do
      plugin = described_class.new(params_valides)
      cols = [Excel::ColumnDescriptor.new(nom: 'Nom', index: 0, type_infere: 'Text')]
      expect(plugin.send(:mapping, cols)).to eq('Nom' => { cible: 'Nom', type: 'Text' })
    end

    it 'accepte la forme courte (source: cible)' do
      plugin = described_class.new(params_valides.merge(colonnes: { 'Nom de famille' => 'Nom' }))
      cols = [Excel::ColumnDescriptor.new(nom: 'Nom de famille', index: 0, type_infere: 'Text')]
      expect(plugin.send(:mapping, cols)).to eq('Nom de famille' => { cible: 'Nom', type: 'Text' })
    end

    it 'accepte la forme longue avec type forcé' do
      plugin = described_class.new(params_valides.merge(
        colonnes: { 'Montant versé' => { 'cible' => 'Montant', 'type' => 'numeric' } }
      ))
      cols = [Excel::ColumnDescriptor.new(nom: 'Montant versé', index: 0, type_infere: 'Text')]
      expect(plugin.send(:mapping, cols)).to eq('Montant versé' => { cible: 'Montant', type: 'Numeric' })
    end

    it 'ignore les colonnes source absentes du fichier et le signale' do
      plugin = described_class.new(params_valides.merge(colonnes: { 'Absente' => 'X' }))
      expect(plugin.send(:mapping, [])).to eq({})
      expect(plugin.erreurs_metier).to include(/Absente/)
    end
  end

  describe 'ensure_colonnes' do
    let(:table) { instance_double(Grist::Table) }

    it 'crée les colonnes cibles manquantes' do
      allow(table).to receive(:columns).and_return('Ligne' => { type: 'Int' })
      allow(table).to receive(:create_columns)

      plugin = described_class.new(params_valides)
      créées = plugin.send(:ensure_colonnes, table, 'Nom' => { cible: 'Nom', type: 'Text' })

      expect(créées).to eq(['Nom'])
      expect(table).to have_received(:create_columns)
    end

    it 'respecte creer_colonnes_manquantes: false' do
      allow(table).to receive(:columns).and_return({})
      plugin = described_class.new(params_valides.merge(options: { 'creer_colonnes_manquantes' => false }))

      expect(plugin.send(:ensure_colonnes, table, 'Nom' => { cible: 'Nom', type: 'Text' })).to eq([])
      expect(table).not_to receive(:create_columns)
    end

    it 'ne modifie jamais le type d’une colonne existante et loggue le conflit' do
      allow(table).to receive(:columns).and_return('Montant' => { id: 'Montant', type: 'Text' })
      plugin = described_class.new(params_valides)

      expect(table).not_to receive(:update_column)
      plugin.send(:ensure_colonnes, table, 'Montant' => { cible: 'Montant', type: 'Numeric' })
      expect(plugin.erreurs_metier.join).to match(/Montant/)
    end
  end
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/excel_vers_grist_spec.rb -e mapping`
Attendu : ÉCHEC — méthodes absentes.

- [ ] **Étape 3 : implémenter**

```ruby
  TYPES_YAML = {
    'text' => 'Text', 'numeric' => 'Numeric', 'int' => 'Int',
    'date' => 'Date', 'datetime' => 'DateTime:UTC', 'bool' => 'Bool',
    'choice' => 'Choice'
  }.freeze

  def erreurs_metier
    @erreurs_metier ||= []
  end

  def mapping(colonnes)
    déclaré = @params[:colonnes]
    return colonnes.to_h { |c| [c.nom, { cible: c.nom, type: c.type_infere }] } if déclaré.blank?

    par_nom = colonnes.index_by(&:nom)
    déclaré.each_with_object({}) do |(source, cible), acc|
      col = par_nom[source]
      if col.nil?
        erreurs_metier << "Colonne source absente du fichier : #{source}"
        next
      end
      acc[source] = normaliser_cible(cible, col)
    end
  end

  def normaliser_cible(cible, colonne)
    if cible.is_a?(Hash)
      type = TYPES_YAML[cible['type'].to_s.downcase] || colonne.type_infere
      { cible: cible['cible'] || colonne.nom, type: type }
    else
      { cible: cible, type: colonne.type_infere }
    end
  end

  # Type figé à la création : un conflit de type sur une colonne existante est
  # rapporté, jamais appliqué (spec §7.1). Le workflow assumé est : traiter un
  # premier fichier, ajuster les types à la main dans Grist, retraiter.
  def ensure_colonnes(table, mapping)
    existantes = table.columns
    manquantes = mapping.values.reject { |m| existantes.key?(m[:cible]) }

    mapping.each_value do |m|
      meta = existantes[m[:cible]]
      next if meta.nil? || meta[:type] == m[:type]

      message = "Type divergent sur #{m[:cible]} : Grist=#{meta[:type]}, attendu=#{m[:type]} (non modifié)"
      Rails.logger.warn "ExcelVersGrist: #{message}"
      erreurs_metier << message
    end

    return [] if manquantes.empty? || @params.dig(:options, 'creer_colonnes_manquantes') == false

    table.create_columns(manquantes.map { |m| { id: m[:cible], fields: { label: m[:cible], type: m[:type] } } })
    noms = manquantes.map { |m| m[:cible] }
    Rails.logger.info "ExcelVersGrist: colonnes créées : #{noms.join(', ')}"
    noms
  end
```

- [ ] **Étape 4 : lancer les tests**

Run : `bundle exec rspec spec/lib/excel_vers_grist_spec.rb`
Attendu : PASS.

- [ ] **Étape 5 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add app/lib/excel_vers_grist.rb spec/lib/excel_vers_grist_spec.rb
git commit -m "feat(grist): mapping déclaratif des colonnes et création des colonnes manquantes"
```

---

### Task 10 : Upsert des lignes et suppression des orphelins

Leçons n°4, 5, 10, 11, 12. Clé `(Dossier, Ligne)` — l'index de ligne rend tout dédoublonnage inutile — `Dossier` encodé via `GristRef`, et empreinte écrite **seulement** après succès complet.

**Fichiers :**
- Créer : `app/lib/mes_demarches_to_grist/ligne_upserter.rb`
- Créer : `spec/lib/mes_demarches_to_grist/ligne_upserter_spec.rb`
- Modifier : `app/lib/excel_vers_grist.rb` (méthode `traiter`)

**Interfaces :**
- Produit : `LigneUpserter.new(table, dossier_col_id:, ligne_col_id:, field_metadata:)`, `#upsert_lignes(cle_dossier, lignes)` → nombre de lignes écrites, `#supprimer_orphelins(cle_dossier, nb_lignes)` → nombre supprimé.

- [ ] **Étape 1 : écrire les tests qui échouent**

```ruby
# spec/lib/mes_demarches_to_grist/ligne_upserter_spec.rb
require 'rails_helper'

RSpec.describe MesDemarchesToGrist::LigneUpserter do
  let(:metadata) { { 'Dossier' => { id: 'Dossier', type: 'Ref:Dossiers' }, 'Ligne' => { id: 'Ligne', type: 'Int' } } }
  let(:table) { instance_double(Grist::Table) }
  let(:upserter) { described_class.new(table, field_metadata: metadata) }

  before { allow(table).to receive(:upsert_records) }

  it 'upserte chaque ligne avec la clé (Dossier, Ligne) et le Dossier encodé' do
    upserter.upsert_lignes(617_871, [{ 'Nom' => 'A' }, { 'Nom' => 'B' }])

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.size).to eq(2)
      expect(records.first[:require]).to eq('Dossier' => ['l', 617_871], 'Ligne' => 1)
      expect(records.last[:require]['Ligne']).to eq(2)
      expect(records.first[:fields]['Nom']).to eq('A')
    end
  end

  it 'est idempotent : deux passages produisent la même clé' do
    upserter.upsert_lignes(617_871, [{ 'Nom' => 'A' }])
    upserter.upsert_lignes(617_871, [{ 'Nom' => 'A' }])
    expect(table).to have_received(:upsert_records).twice
  end

  it 'supprime les lignes au-delà du nombre courant' do
    allow(table).to receive(:find_by).with('Dossier', ['l', 617_871]).and_return([
      { 'id' => 10, 'fields' => { 'Ligne' => 1 } },
      { 'id' => 11, 'fields' => { 'Ligne' => 2 } },
      { 'id' => 12, 'fields' => { 'Ligne' => 3 } }
    ])
    allow(table).to receive(:delete_records)

    expect(upserter.supprimer_orphelins(617_871, 1)).to eq(2)
    expect(table).to have_received(:delete_records).with([11, 12])
  end

  it 'ne supprime rien quand le fichier n’a pas rétréci' do
    allow(table).to receive(:find_by).and_return([{ 'id' => 10, 'fields' => { 'Ligne' => 1 } }])
    expect(upserter.supprimer_orphelins(617_871, 1)).to eq(0)
  end
end
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/mes_demarches_to_grist/ligne_upserter_spec.rb`
Attendu : ÉCHEC — `uninitialized constant`.

- [ ] **Étape 3 : implémenter**

```ruby
# frozen_string_literal: true

require_relative 'grist_ref'

module MesDemarchesToGrist
  # Upsert des lignes d'une table Grist liée au dossier, clé (Dossier, Ligne).
  #
  # L'index de ligne comme clé rend tout dédoublonnage inutile : deux lignes
  # source identiques restent deux lignes distinctes, et un re-run réécrit les
  # mêmes clés au lieu de créer des doublons.
  class LigneUpserter
    def initialize(table, dossier_col_id: 'Dossier', ligne_col_id: 'Ligne', field_metadata: {})
      @table = table
      @dossier_col_id = dossier_col_id
      @ligne_col_id = ligne_col_id
      @field_metadata = field_metadata
    end

    def upsert_lignes(cle_dossier, lignes)
      return 0 if lignes.empty?

      records = lignes.each_with_index.map do |ligne, index|
        cle = { @dossier_col_id => cle_encodee(cle_dossier), @ligne_col_id => index + 1 }
        { require: cle, fields: ligne.merge(cle) }
      end

      @table.upsert_records(records)
      records.size
    end

    def supprimer_orphelins(cle_dossier, nb_lignes)
      existantes = @table.find_by(@dossier_col_id, cle_encodee(cle_dossier))
      orphelins = existantes.select { |r| r.dig('fields', @ligne_col_id).to_i > nb_lignes }.map { |r| r['id'] }
      return 0 if orphelins.empty?

      @table.delete_records(orphelins)
      Rails.logger.info "ExcelVersGrist: #{orphelins.size} ligne(s) orpheline(s) supprimée(s)"
      orphelins.size
    end

    private

    def cle_encodee(valeur)
      GristRef.encode_key(valeur, @field_metadata.dig(@dossier_col_id, :type))
    end
  end
end
```

- [ ] **Étape 4 : lancer les tests**

Run : `bundle exec rspec spec/lib/mes_demarches_to_grist/ligne_upserter_spec.rb`
Attendu : PASS.

- [ ] **Étape 5 : écrire le test de bout en bout du plugin (empreinte non écrite si échec)**

```ruby
  describe 'traitement complet' do
    it "n'écrit pas l'empreinte quand l'upsert échoue" do
      plugin = described_class.new(params_valides.merge(options: { 'continuer_si_erreur' => true }))
      table = instance_double(Grist::Table, columns: { 'Ligne' => { type: 'Int' } })
      allow(Grist::Config).to receive(:table).and_return(table)
      allow(table).to receive(:upsert_records).and_raise(Grist::APIError.new('boom'))

      expect(table).not_to receive(:update_records)
      # le traitement ne doit pas relever puisque continuer_si_erreur est vrai
      expect { plugin.send(:ecrire_empreinte, table, 1, 'aaa') }.not_to raise_error
    end
  end
```

- [ ] **Étape 6 : brancher `traiter` dans le plugin**

```ruby
  def traiter(_demarche, dossier, fichiers)
    empreinte = empreinte_source(fichiers)
    table_lignes = Grist::Config.table(@params[:grist]['doc_id'], @params[:grist]['table_id'], @params[:grist]['token_config'])
    table_principale = table_principale_pour(@params[:grist])

    ensure_colonne_empreinte(table_principale)
    ligne_principale = trouver_ligne_principale(table_principale, dossier.number)
    return Rails.logger.info("ExcelVersGrist: dossier #{dossier.number} à jour, rien à faire") if a_jour?(empreinte, ligne_principale)

    lignes, colonnes = extraire(fichiers)
    correspondance = mapping(colonnes)
    ensure_colonnes(table_lignes, correspondance)

    lignes_cibles = projeter(lignes, correspondance)
    upserter = MesDemarchesToGrist::LigneUpserter.new(table_lignes, field_metadata: table_lignes.columns)
    upserter.upsert_lignes(dossier.number, lignes_cibles)
    upserter.supprimer_orphelins(dossier.number, lignes_cibles.size)

    # L'empreinte n'est écrite qu'ici : tout échec en amont laisse le dossier à
    # retraiter au passage suivant. Le workflow n8n écrivait l'empreinte sur une
    # branche parallèle à l'upsert — un échec y perdait les lignes en silence.
    ecrire_empreinte(table_principale, ligne_principale, empreinte)
    ecrire_erreurs(table_principale, ligne_principale)
  end

  def extraire(fichiers)
    fichier = fichiers.last
    PieceJustificativeCache.get(fichier) do |chemin|
      reader = Excel::SheetReader.new(chemin, feuille: @params[:feuille])
      [reader.lignes, reader.colonnes]
    ensure
      reader&.close
    end
  end

  def projeter(lignes, correspondance)
    lignes.filter_map do |ligne|
      projetee = correspondance.each_with_object({}) do |(source, m), acc|
        acc[m[:cible]] = Excel::SheetReader.coercer(ligne[source], m[:type])
      end
      next if projetee.values.all?(&:blank?)

      projetee
    end
  end
```

Les méthodes `table_principale_pour`, `trouver_ligne_principale`, `ecrire_empreinte` s'appuient sur `@params[:grist]['table_principale']` (défaut `'Dossiers'`) et `Grist::Table#update_records`.

- [ ] **Étape 7 : lancer la suite complète**

Run : `bundle exec rspec spec/lib/excel_vers_grist_spec.rb spec/lib/mes_demarches_to_grist/`
Attendu : tout vert.

- [ ] **Étape 8 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add app/lib/ spec/lib/
git commit -m "feat(grist): upsert des lignes Excel par (Dossier, Ligne) avec suppression des orphelins"
```

---

### Task 11 : Colonne d'erreurs métier

Leçons n°8 et 10. Rend visibles dans Grist les erreurs de données, vidée en cas de succès.

**Fichiers :**
- Modifier : `app/lib/excel_vers_grist.rb`
- Modifier : `spec/lib/excel_vers_grist_spec.rb`

**Interfaces :**
- Produit : `#ecrire_erreurs(table, ligne_principale)` — écrit `erreurs_metier` concaténées dans la colonne `options.colonne_erreurs` si configurée, ou `''` si aucune erreur. Colonne auto-créée quand l'option est présente.

- [ ] **Étape 1 : écrire les tests qui échouent**

```ruby
  describe 'colonne d’erreurs' do
    let(:table) { instance_double(Grist::Table) }
    let(:plugin) { described_class.new(params_valides.merge(options: { 'colonne_erreurs' => 'Erreurs sync' })) }

    before do
      allow(table).to receive(:columns).and_return({})
      allow(table).to receive(:create_columns)
      allow(table).to receive(:update_records)
    end

    it 'écrit les messages métier accumulés' do
      plugin.erreurs_metier << 'Feuille "X" introuvable'
      plugin.send(:ecrire_erreurs, table, { 'id' => 4 })

      expect(table).to have_received(:update_records) do |records|
        expect(records.first[:fields]['Erreurs sync']).to eq('Feuille "X" introuvable')
      end
    end

    it 'vide la colonne en cas de succès' do
      plugin.send(:ecrire_erreurs, table, { 'id' => 4 })
      expect(table).to have_received(:update_records) do |records|
        expect(records.first[:fields]['Erreurs sync']).to eq('')
      end
    end

    it 'ne fait rien si l’option n’est pas configurée' do
      sans = described_class.new(params_valides)
      sans.send(:ecrire_erreurs, table, { 'id' => 4 })
      expect(table).not_to have_received(:update_records)
    end
  end
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bundle exec rspec spec/lib/excel_vers_grist_spec.rb -e "colonne d"`
Attendu : ÉCHEC — méthode absente.

- [ ] **Étape 3 : implémenter**

```ruby
  def colonne_erreurs
    @params.dig(:options, 'colonne_erreurs')
  end

  # Colonne technique requise par l'option : auto-créée indépendamment de
  # creer_colonnes_manquantes. Vidée en cas de succès pour ne pas laisser
  # traîner l'erreur d'un passage précédent.
  def ecrire_erreurs(table, ligne_principale)
    return if colonne_erreurs.blank? || ligne_principale.nil?

    unless table.columns.key?(colonne_erreurs)
      table.create_columns([{ id: colonne_erreurs, fields: { label: colonne_erreurs, type: 'Text' } }])
    end

    table.update_records([{ id: ligne_principale['id'], fields: { colonne_erreurs => erreurs_metier.join(' ; ') } }])
  end
```

- [ ] **Étape 4 : lancer les tests**

Run : `bundle exec rspec spec/lib/excel_vers_grist_spec.rb`
Attendu : tout vert.

- [ ] **Étape 5 : suite complète du projet**

Run : `bundle exec rspec`
Attendu : aucune régression.

- [ ] **Étape 6 : rubocop, lint, commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add app/lib/excel_vers_grist.rb spec/lib/excel_vers_grist_spec.rb
git commit -m "feat(grist): colonne d'erreurs métier pour excel_vers_grist"
```

---

## Phase 3 — Validation live sur les pesticides et retrait de n8n

### Task 12 : Reprendre le cas pesticides, puis décommissionner le workflow n8n

Le cas pesticides est le **test d'acceptation** du plugin : le workflow n8n tourne en production depuis mars, ses résultats sont la référence de comparaison.

**Fichiers :**
- Modifier : `storage/configurations/dbs_pesticides.yml` (ajout de la tâche `excel_vers_grist`)
- Puis : `deployment/robot-mes-demarches-staging/configurations/` (test), enfin `deployment/robot-mes-demarches-production/configurations/`

**Prérequis :** la recopie des dossiers vers Grist (`grist_sync` sur la 1536) doit être déployée et alimenter la table `Dossiers` — c'est le premier maillon remis en service le 07/08/2026.

- [ ] **Étape 1 : vérifier en amont l'encodage `Ref` sur une ligne réelle**

Sur un dossier bac-à-sable, écrire une ligne dans `Substances` via `LigneUpserter` et vérifier dans Grist que la colonne `Dossier` **affiche bien le numéro** (et non une cellule vide). C'est la vérification directe de la leçon n°1 ; ne pas passer à l'étape suivante sans elle.

- [ ] **Étape 2 : ajouter la tâche à la configuration**

```yaml
dbs_excel_substances: &dbs_excel_substances
  etat_du_dossier: [ accepte ]
  champ: "Excel avec avis"
  feuille: "Formulaire de saisie"
  grist:
    doc_id: 'tYVZeA7kfoWQ'
    table_id: 'Substances'
    table_principale: 'Dossiers'
  options:
    creer_colonnes_manquantes: false     # schéma Substances déjà établi
    continuer_si_erreur: true
    colonne_erreurs: "Message d'erreur"
    colonne_empreinte: "excel_checksum"
  colonnes:
    "Substances actives": "Nom"
    "Noms commerciaux": "Nom_commercial"
    "Concentrations":
      cible: "Concentration"
      type: numeric
    "Poids/Volume total":
      cible: "Poids_volume_total"
      type: numeric
    "Unité de mesure": "Unite"
```

et dans `when_ok`, **après** `grist_sync` (la ligne principale doit exister avant qu'on y écrive l'empreinte) :

```yaml
    - grist_sync: *dbs_grist_dossiers
    - excel_vers_grist: *dbs_excel_substances
```

- [ ] **Étape 3 : valider la configuration hors ligne**

```bash
ruby -ryaml -e "YAML.load_file('storage/configurations/dbs_pesticides.yml', aliases: true)"
bin/rails runner 'd=YAML.load_file("storage/configurations/dbs_pesticides.yml", aliases: true); b=d.find { |_k,v| v.is_a?(Hash) && v.key?("demarches") }.last; InspectorTask.create_tasks(b["when_ok"]).each { |t| puts "#{t.name} valid?=#{t.valid?} #{t.errors.inspect}" }'
```

Attendu : les trois tâches valides, aucune erreur.

- [ ] **Étape 4 : rejouer un dossier réel déjà traité par n8n, et comparer**

Choisir un dossier accepté dont `Nb_substances > 0`, noter les lignes `Substances` existantes, puis :

```bash
bin/rails runner 'VerificationService.new.check_one(617871)'
```

Comparer les lignes produites avec celles de n8n : mêmes noms, mêmes concentrations, mêmes poids, mêmes unités. Tout écart est un bug du plugin, à corriger avant de continuer. **Attention à l'unité** : `Unite` est un `Choice` — vérifier que les valeurs du fichier tombent dans la liste (`Kg`, `L`), sinon la normalisation manque (leçon n°8) et doit être ajoutée au mapping.

- [ ] **Étape 5 : traiter le reliquat et mesurer**

Vérifier le nombre de dossiers acceptés à `excel_checksum = "-"` avant/après quelques cycles, et l'absence de doublons dans `Substances` (une même `(Dossier, Ligne)` ne doit jamais apparaître deux fois).

- [ ] **Étape 6 : couper n8n**

Une fois le plugin confirmé sur un lot représentatif : **désactiver** le workflow `BoS7lRfdrOYCcmdE` (ne pas le supprimer — le garder comme référence et comme filet de repli). Consigner la date de coupure dans le fichier de configuration.

- [ ] **Étape 7 : commit**

```bash
bundle exec rubocop -A
bundle exec rake lint
git add docs/superpowers/plans/2026-08-07-excel-vers-grist.md
git commit -m "docs(grist): plan et configuration pesticides pour excel_vers_grist"
```

---

## Auto-revue

**Couverture de la spec**

| Exigence spec | Tâche |
|---|---|
| §4.1 sélection de feuille (nom/position, défaut 1ʳᵉ) | 3 |
| §4.1 descripteur de colonnes (nom sanitizé, type, en-tête brut) | 3, 4, 5 |
| §4.2 gating `must_check?` / `etat_du_dossier` | 7 |
| §4.2 gate checksum #2 | 8 |
| §4.2 `ensure_columns` + colonne technique | 8, 9 |
| §4.2 upsert via réutilisation | 10 |
| §4.2 collecte des erreurs métier | 9, 11 |
| §4.2 Sentry + `continuer_si_erreur` | 7 |
| §5 configuration YAML (toutes les clés) | 7, 9, 12 |
| §6 empreinte multi-fichiers triée en CSV, stockée sur la main row | 8 |
| §7.1 création de colonnes, opt-out, type figé | 9 |
| §7.2 inférence de type | 5 |
| §7.3 sanitization (doublons, en-têtes vides) | 4 |
| §7.4 matching par nom, dérive de schéma | 9 |
| §8 point 1 (spec `SyncCoordinator`) | 1 |
| §8 point 2 (sémantique upsert `require` sur `Ref`) | **2** — tranché par le terrain, plus une inconnue |
| §9 gestion d'erreurs, empreinte non écrite si échec | 7, 10 |
| §9 colonne d'erreurs (cycle de vie) | 11 |
| §10 corpus de fichiers tordus | 3, 4, 5, 6 |

**Hors périmètre confirmé** (spec §2) : CSV, recopie du binaire xlsx, synchro des avis. §8 point 3 (router les lignes de bloc via `RowUpserter` pour le diff) n'est pas repris : `LigneUpserter` s'appuie sur l'idempotence serveur de l'upsert natif, le diff ligne-à-ligne serait une optimisation prématurée ici.

**Cohérence des types** : `GristRef.encode_key` / `.ref?` (Task 2) sont utilisés à l'identique dans `RowUpserter` (Task 2) et `LigneUpserter` (Task 10). `Excel::ColumnDescriptor` expose `nom`, `en_tete_brut`, `index`, `type_infere` dans les Tasks 3 à 6 et 9. `SheetReader.coercer(valeur, type)` (Task 6) est appelé avec les types de `TYPES_YAML` (Task 9), tous alignés sur les types Grist (`Text`, `Numeric`, `Int`, `Date`, `DateTime:UTC`, `Bool`, `Choice`).

**Point d'attention pour l'exécutant** : Task 5 introduit un balayage des lignes pour inférer les types, alors que Task 3 construit les lignes à partir des colonnes. Vérifier l'absence de récursion (`ligne_de_donnees?` ne doit pas appeler `colonnes`) et envisager un seul balayage mémorisé si les fichiers réels sont volumineux.
