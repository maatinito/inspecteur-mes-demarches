# Synchronisation des avis vers Baserow — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Étendre le plugin `baserow_sync` pour synchroniser, pour chaque dossier, ses avis (question/réponse + pièces jointes) vers une table Baserow dédiée `Avis`, avec builder admin idempotent pour créer la structure.

**Architecture:** Catégorie dédiée `avis` parallèle à `repetable_blocks` dans `SyncCoordinator`. Nouveau module GraphQL partagé `MesDemarches::AvisFetcher`, nouveau `AvisSyncer` pour l'orchestration sync, nouveau `AvisTableBuilder` pour la création/maj structure via UI admin. Réutilisation maximale de `RowUpserter`, `normalize_files`, gestion des fichiers existante.

**Tech Stack:** Ruby on Rails, RSpec, WebMock, GraphQL (`graphql-client`), Baserow API.

**Spec source:** `docs/superpowers/specs/2026-05-26-baserow-sync-avis-design.md`

---

## File Structure

**À créer :**
- `app/lib/mes_demarches/avis_fetcher.rb` — module GraphQL partagé
- `app/lib/mes_demarches_to_baserow/avis_syncer.rb` — orchestration sync
- `app/lib/mes_demarches_to_baserow/avis_table_builder.rb` — création/maj structure
- `spec/lib/mes_demarches/avis_fetcher_spec.rb`
- `spec/lib/mes_demarches_to_baserow/avis_syncer_spec.rb`
- `spec/lib/mes_demarches_to_baserow/avis_table_builder_spec.rb`

**À modifier :**
- `app/lib/mes_demarches_to_baserow/data_extractor.rb` — extraire `normalize_file_array` + ajouter `extract_avis_row`
- `app/lib/mes_demarches_to_baserow/sync_coordinator.rb` — ajouter étape `sync_avis`
- `app/lib/baserow_sync.rb` — `require_relative` pour le nouveau module
- `app/controllers/admin/baserow_schema_controller.rb` — actions `preview_avis_table`, `build_avis_table`
- `app/views/admin/baserow_schema/repetable_blocks.html.haml` — section UI pour le builder Avis
- `config/routes.rb` — routes admin pour les deux nouvelles actions
- `spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb` — couvrir `extract_avis_row` + refactor `normalize_files`

**Index lookup repère** (pour bien situer les modifs) :
- `sync_coordinator.rb:41-80` : méthode `sync_dossier` (le hook d'insertion sera après `sync_repetable_blocks`)
- `data_extractor.rb:295-340` : méthode `normalize_files` (à refactoriser)
- `baserow_schema_controller.rb:175-185` : voisin des actions `preview_repetable_blocks`/`build_repetable_blocks`

---

## Phase 1 — Couche de sync (foundation)

### Task 1 : Module `MesDemarches::AvisFetcher`

**Files:**
- Create: `app/lib/mes_demarches/avis_fetcher.rb`
- Create: `spec/lib/mes_demarches/avis_fetcher_spec.rb`

**But :** Encapsuler la requête GraphQL des avis (avec attachments) dans un module partagé. Retour : `Array<Avis>` (ou `[]` en cas d'erreur).

- [ ] **Step 1.1 : Écrire le spec en échec**

Créer `spec/lib/mes_demarches/avis_fetcher_spec.rb` :

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarches::AvisFetcher do
  describe '.fetch' do
    let(:dossier_number) { 12_345 }

    context 'quand la requête GraphQL réussit avec des avis' do
      let(:graphql_response) do
        double(
          'GraphQLResponse',
          errors: double('Errors', present?: false),
          data: double('Data', dossier: double('Dossier', avis: %i[avis1 avis2]))
        )
      end

      before do
        allow(MesDemarches).to receive(:query).and_return(graphql_response)
      end

      it 'retourne la liste des avis' do
        expect(described_class.fetch(dossier_number)).to eq(%i[avis1 avis2])
      end
    end

    context 'quand le dossier n\'a pas d\'avis' do
      let(:graphql_response) do
        double(
          'GraphQLResponse',
          errors: double('Errors', present?: false),
          data: double('Data', dossier: double('Dossier', avis: nil))
        )
      end

      before do
        allow(MesDemarches).to receive(:query).and_return(graphql_response)
      end

      it 'retourne un tableau vide' do
        expect(described_class.fetch(dossier_number)).to eq([])
      end
    end

    context 'quand la requête GraphQL échoue' do
      let(:graphql_response) do
        double(
          'GraphQLResponse',
          errors: double('Errors', present?: true, messages: { '' => ['Erreur réseau'] }),
          data: nil
        )
      end

      before do
        allow(MesDemarches).to receive(:query).and_return(graphql_response)
        allow(Rails.logger).to receive(:error)
      end

      it 'log l\'erreur et retourne un tableau vide' do
        result = described_class.fetch(dossier_number)
        expect(result).to eq([])
        expect(Rails.logger).to have_received(:error).with(/AvisFetcher.*12345/)
      end
    end
  end
end
```

- [ ] **Step 1.2 : Vérifier l'échec du test**

```bash
bundle exec rspec spec/lib/mes_demarches/avis_fetcher_spec.rb
```

Attendu : `NameError` ou `LoadError` (module inexistant).

- [ ] **Step 1.3 : Implémenter le module**

Créer `app/lib/mes_demarches/avis_fetcher.rb` :

```ruby
# frozen_string_literal: true

module MesDemarches
  # Récupère les avis d'un dossier Mes-Démarches via GraphQL,
  # avec leurs pièces jointes (attachments).
  #
  # Module partagé entre BaserowSync (synchronisation vers Baserow)
  # et potentiellement AvisToBlocRepetable (refactor ultérieur).
  module AvisFetcher
    Query = MesDemarches::Client.parse <<-GRAPHQL
      query DossierAvis($dossier: Int!) {
        dossier(number: $dossier) {
          avis {
            id
            question
            reponse
            questionLabel
            questionAnswer
            dateQuestion
            dateReponse
            expert { id, email }
            claimant { id, email }
            attachments {
              filename
              byteSize
              url
              contentType
            }
          }
        }
      }
    GRAPHQL

    def self.fetch(dossier_number)
      result = MesDemarches.query(Query::DossierAvis, variables: { dossier: dossier_number })

      if result.errors.present?
        Rails.logger.error(
          "AvisFetcher: erreur GraphQL pour dossier #{dossier_number}: " \
          "#{result.errors.messages.values.flatten.join(', ')}"
        )
        return []
      end

      result.data&.dossier&.avis || []
    rescue StandardError => e
      Rails.logger.error("AvisFetcher: exception pour dossier #{dossier_number}: #{e.message}")
      []
    end
  end
end
```

- [ ] **Step 1.4 : Vérifier que les tests passent**

```bash
bundle exec rspec spec/lib/mes_demarches/avis_fetcher_spec.rb
```

Attendu : 3 examples, 0 failures.

- [ ] **Step 1.5 : Lint**

```bash
bundle exec rubocop -A app/lib/mes_demarches/avis_fetcher.rb spec/lib/mes_demarches/avis_fetcher_spec.rb
```

Attendu : pas d'offenses (ou auto-corrigées).

- [ ] **Step 1.6 : Commit**

```bash
git add app/lib/mes_demarches/avis_fetcher.rb spec/lib/mes_demarches/avis_fetcher_spec.rb
git commit -m "feat(baserow_sync): module AvisFetcher pour query GraphQL avis avec attachments"
```

---

### Task 2 : Refactor `DataExtractor.normalize_files` en `normalize_file_array`

**Files:**
- Modify: `app/lib/mes_demarches_to_baserow/data_extractor.rb:295-340`
- Modify: `spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb` (tests existants doivent passer)

**But :** Extraire le cœur de `normalize_files(champ, existing_files)` en `normalize_file_array(files, existing_files)` qui accepte une `Array<File>` brute (utilisable autant pour `champ.files` que pour `avis.attachments`).

- [ ] **Step 2.1 : Écrire un test pour la nouvelle méthode `normalize_file_array`**

Ajouter dans `spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb` (dans le `describe MesDemarchesToBaserow::DataExtractor do`) :

```ruby
  describe '#normalize_file_array' do
    let(:file1) { double('File', filename: 'avis.pdf', url: 'https://example.com/avis.pdf', byte_size: 5000) }
    let(:file2) { double('File', filename: 'annexe.pdf', url: 'https://example.com/annexe.pdf', byte_size: 1000) }

    context 'sans fichiers existants' do
      it 'retourne tous les fichiers comme nouveaux (avec url)' do
        result = extractor.send(:normalize_file_array, [file1, file2], [])

        expect(result).to contain_exactly(
          { url: 'https://example.com/avis.pdf', visible_name: 'avis.pdf' },
          { url: 'https://example.com/annexe.pdf', visible_name: 'annexe.pdf' }
        )
      end
    end

    context 'avec un fichier déjà présent (même nom + taille)' do
      let(:existing_files) do
        [{ 'name' => 'baserow_hash_avis', 'visible_name' => 'avis.pdf', 'size' => 5000 }]
      end

      it 'réutilise le hash Baserow pour le fichier existant et upload le nouveau' do
        result = extractor.send(:normalize_file_array, [file1, file2], existing_files)

        expect(result).to contain_exactly(
          { 'name' => 'baserow_hash_avis', 'visible_name' => 'avis.pdf' },
          { url: 'https://example.com/annexe.pdf', visible_name: 'annexe.pdf' }
        )
      end
    end

    context 'avec une liste vide' do
      it 'retourne un tableau vide' do
        result = extractor.send(:normalize_file_array, [], [])
        expect(result).to eq([])
      end
    end

    context 'avec liste vide mais fichiers existants' do
      let(:existing_files) do
        [{ 'name' => 'h1', 'visible_name' => 'avis.pdf', 'size' => 5000 }]
      end

      it 'retourne les fichiers existants (préservation)' do
        result = extractor.send(:normalize_file_array, [], existing_files)
        expect(result).to eq(existing_files)
      end
    end
  end
```

- [ ] **Step 2.2 : Vérifier l'échec**

```bash
bundle exec rspec spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb -e "normalize_file_array"
```

Attendu : FAIL avec `NoMethodError: undefined method 'normalize_file_array'`.

- [ ] **Step 2.3 : Refactorer `normalize_files`**

Dans `app/lib/mes_demarches_to_baserow/data_extractor.rb`, remplacer la méthode `normalize_files` (lignes ~295-340) par :

```ruby
    # Wrapper pour les champs MD (PieceJustificativeChamp).
    # Délègue à normalize_file_array sur champ.files.
    def normalize_files(champ, existing_files = [])
      return existing_files if champ.__typename != 'PieceJustificativeChamp' || champ.files.blank?

      normalize_file_array(champ.files, existing_files)
    rescue StandardError => e
      Rails.logger.warn "BaserowSync: Erreur normalisation fichiers: #{e.message}"
      raise
    end

    # Normalise une Array<File> (GraphQL) en payload Baserow.
    # Réutilisable pour PieceJustificativeChamp.files ET Avis.attachments.
    #
    # Stratégie : pour chaque fichier MD, chercher s'il existe déjà côté Baserow
    # (même nom visible + même taille). Si oui, réutiliser le hash Baserow ;
    # sinon, envoyer l'URL pour upload.
    #
    # rubocop:disable Metrics/MethodLength
    def normalize_file_array(files, existing_files = [])
      return existing_files if files.blank?

      baserow_files = existing_files.is_a?(Array) ? existing_files : []
      existing_file_index = baserow_files.map do |f|
        {
          visible_name: f['visible_name'],
          size: f['size'],
          baserow_hash: f['name']
        }
      end.compact

      all_files = files.filter_map do |file|
        filename = file.filename.to_s.strip
        next if filename.blank?

        existing = existing_file_index.find do |sig|
          sig[:visible_name] == filename && sig[:size] == file.byte_size
        end

        if existing
          { 'name' => existing[:baserow_hash], 'visible_name' => filename }
        else
          Rails.logger.debug "BaserowSync: Préparation upload nouveau fichier '#{filename}' depuis #{file.url}"
          { url: file.url, visible_name: filename }
        end
      end

      new_count = all_files.count { |f| f.key?(:url) }
      Rails.logger.info "BaserowSync: #{new_count} nouveau(x) fichier(s) à uploader" if new_count.positive?

      all_files
    end
    # rubocop:enable Metrics/MethodLength
```

- [ ] **Step 2.4 : Vérifier que TOUS les tests data_extractor passent (anciens + nouveaux)**

```bash
bundle exec rspec spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb
```

Attendu : tous les examples passent. **Important :** les anciens tests `#normalize_files` doivent continuer à passer (rétrocompat).

- [ ] **Step 2.5 : Lint**

```bash
bundle exec rubocop -A app/lib/mes_demarches_to_baserow/data_extractor.rb spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb
```

- [ ] **Step 2.6 : Commit**

```bash
git add app/lib/mes_demarches_to_baserow/data_extractor.rb spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb
git commit -m "refactor(baserow_sync): extraire normalize_file_array de normalize_files"
```

---

### Task 3 : `DataExtractor.extract_avis_row`

**Files:**
- Modify: `app/lib/mes_demarches_to_baserow/data_extractor.rb`
- Modify: `spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb`

**But :** Convertir un objet GraphQL `Avis` (incluant `attachments`) en hash prêt à upserter dans la table Baserow `Avis`. Respecte les colonnes présentes dans `field_metadata` (skip silencieux des absentes).

**Mapping cible (cf. spec) :**

| Clé hash | Source | Normalisation |
|---|---|---|
| `Avis` | `avis.id` | `to_s` |
| `Dossier` | `main_row_id` (passé en paramètre) | `to_s` (sera remplacé par `[main_row_id]` côté SyncCoordinator) |
| `Question` | `avis.question` | brute |
| `Réponse` | `avis.reponse` | brute |
| `Libellé question` | `avis.question_label` | brute |
| `Réponse fermée` | `avis.question_answer` | Boolean tel quel |
| `Date question` | `avis.date_question` | `format_date` ou `format_datetime` selon type Baserow |
| `Date réponse` | `avis.date_reponse` | idem |
| `Email expert` | `avis.expert&.email` | brute |
| `Email demandeur` | `avis.claimant&.email` | brute |
| `Pièces jointes` | `avis.attachments` | `normalize_file_array(attachments, existing_files)` |

- [ ] **Step 3.1 : Écrire le test (en échec)**

Ajouter dans `spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb` :

```ruby
  describe '#extract_avis_row' do
    let(:avis_field_metadata) do
      {
        'Avis' => { 'type' => 'text', 'id' => 100, 'primary' => true },
        'Dossier' => { 'type' => 'link_row', 'id' => 101 },
        'Question' => { 'type' => 'long_text', 'id' => 102 },
        'Réponse' => { 'type' => 'long_text', 'id' => 103 },
        'Libellé question' => { 'type' => 'text', 'id' => 104 },
        'Réponse fermée' => { 'type' => 'boolean', 'id' => 105 },
        'Date question' => { 'type' => 'date', 'id' => 106 },
        'Date réponse' => { 'type' => 'date', 'id' => 107 },
        'Email expert' => { 'type' => 'email', 'id' => 108 },
        'Email demandeur' => { 'type' => 'email', 'id' => 109 },
        'Pièces jointes' => { 'type' => 'file', 'id' => 110 }
      }
    end

    let(:expert) { double('Profile', id: 'exp-1', email: 'expert@example.com') }
    let(:claimant) { double('Profile', id: 'cla-1', email: 'demandeur@example.com') }
    let(:attachment) { double('File', filename: 'avis.pdf', url: 'https://md.gp.pf/avis.pdf', byte_size: 5000) }

    let(:avis) do
      double(
        'Avis',
        id: 'QXZpcy0xMjM=',
        question: 'Quel est votre avis ?',
        reponse: 'Favorable',
        question_label: nil,
        question_answer: nil,
        date_question: '2026-05-01T10:00:00Z',
        date_reponse: '2026-05-15T14:30:00Z',
        expert: expert,
        claimant: claimant,
        attachments: [attachment]
      )
    end

    let(:extractor_avis) { described_class.new(avis_field_metadata, {}) }

    it 'extrait tous les champs présents dans field_metadata' do
      row = extractor_avis.extract_avis_row(avis, 42, [])

      expect(row['Avis']).to eq('QXZpcy0xMjM=')
      expect(row['Dossier']).to eq('42') # sera traduit en [id] côté SyncCoordinator
      expect(row['Question']).to eq('Quel est votre avis ?')
      expect(row['Réponse']).to eq('Favorable')
      expect(row['Date question']).to eq('2026-05-01')
      expect(row['Date réponse']).to eq('2026-05-15')
      expect(row['Email expert']).to eq('expert@example.com')
      expect(row['Email demandeur']).to eq('demandeur@example.com')
      expect(row['Pièces jointes']).to contain_exactly(
        { url: 'https://md.gp.pf/avis.pdf', visible_name: 'avis.pdf' }
      )
    end

    it 'gère expert et claimant absents' do
      allow(avis).to receive(:expert).and_return(nil)
      allow(avis).to receive(:claimant).and_return(nil)

      row = extractor_avis.extract_avis_row(avis, 42, [])

      expect(row).not_to have_key('Email expert')
      expect(row).not_to have_key('Email demandeur')
    end

    it 'skip les colonnes absentes de field_metadata' do
      partial_metadata = { 'Avis' => { 'type' => 'text' }, 'Dossier' => { 'type' => 'link_row' } }
      extractor = described_class.new(partial_metadata, {})

      row = extractor.extract_avis_row(avis, 42, [])

      expect(row.keys).to contain_exactly('Avis', 'Dossier')
    end

    it 'réutilise les PJ déjà uploadées (déduplication par nom+taille)' do
      existing_pjs = [{ 'name' => 'hash_avis', 'visible_name' => 'avis.pdf', 'size' => 5000 }]
      row = extractor_avis.extract_avis_row(avis, 42, existing_pjs)

      expect(row['Pièces jointes']).to contain_exactly(
        { 'name' => 'hash_avis', 'visible_name' => 'avis.pdf' }
      )
    end

    it 'omet "Pièces jointes" quand avis.attachments est vide ET pas d\'existant' do
      allow(avis).to receive(:attachments).and_return([])
      row = extractor_avis.extract_avis_row(avis, 42, [])

      expect(row).not_to have_key('Pièces jointes')
    end
  end
```

- [ ] **Step 3.2 : Vérifier l'échec**

```bash
bundle exec rspec spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb -e "extract_avis_row"
```

Attendu : FAIL `NoMethodError: undefined method 'extract_avis_row'`.

- [ ] **Step 3.3 : Implémenter `extract_avis_row`**

Ajouter dans `app/lib/mes_demarches_to_baserow/data_extractor.rb`, dans la partie publique (avant `private`) :

```ruby
    # Construit le hash de données pour une ligne de la table Baserow `Avis`.
    #
    # @param avis [Object] objet GraphQL Avis (id, question, reponse, expert, attachments, etc.)
    # @param main_row_id [Integer] ID de la row principale du dossier (pour le link_row Dossier)
    # @param existing_attachments [Array<Hash>] PJ déjà uploadées dans la row Avis existante
    # @return [Hash] payload filtré selon les colonnes présentes dans field_metadata
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def extract_avis_row(avis, main_row_id, existing_attachments = [])
      candidates = {
        'Avis' => avis.id.to_s,
        'Dossier' => main_row_id.to_s,
        'Question' => avis.question,
        'Réponse' => avis.reponse,
        'Libellé question' => avis.question_label,
        'Réponse fermée' => avis.question_answer,
        'Email expert' => avis.expert&.email,
        'Email demandeur' => avis.claimant&.email
      }

      candidates['Date question'] = normalize_avis_date(avis.date_question, 'Date question')
      candidates['Date réponse'] = normalize_avis_date(avis.date_reponse, 'Date réponse')
      candidates['Pièces jointes'] = normalize_avis_attachments(avis.attachments, existing_attachments)

      # Filtrer selon ce qui existe vraiment dans la table Baserow
      candidates.each_with_object({}) do |(key, value), result|
        next unless @field_metadata.key?(key)
        next if value.nil?
        next if value.is_a?(Array) && value.empty?

        result[key] = value
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
```

Et ajouter dans la partie `private` :

```ruby
    def normalize_avis_date(raw_value, column_name)
      return nil if raw_value.blank?

      type = @field_metadata.dig(column_name, 'type')
      case type
      when 'date'
        format_date(raw_value)
      else
        # Si la colonne n'existe pas ou n'est pas de type date, on retourne la valeur brute
        # (sera filtrée plus tard par le présence dans field_metadata)
        raw_value
      end
    end

    def normalize_avis_attachments(attachments, existing_attachments)
      list = Array(attachments)
      return nil if list.empty? && existing_attachments.blank?

      normalize_file_array(list, existing_attachments)
    end
```

- [ ] **Step 3.4 : Vérifier que les tests passent**

```bash
bundle exec rspec spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb
```

Attendu : tous les examples passent (anciens + 5 nouveaux pour `extract_avis_row`).

- [ ] **Step 3.5 : Lint**

```bash
bundle exec rubocop -A app/lib/mes_demarches_to_baserow/data_extractor.rb spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb
```

- [ ] **Step 3.6 : Commit**

```bash
git add app/lib/mes_demarches_to_baserow/data_extractor.rb spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb
git commit -m "feat(baserow_sync): DataExtractor#extract_avis_row pour la table Avis"
```

---

### Task 4 : `AvisSyncer` (orchestration sync)

**Files:**
- Create: `app/lib/mes_demarches_to_baserow/avis_syncer.rb`
- Create: `spec/lib/mes_demarches_to_baserow/avis_syncer_spec.rb`

**But :** Orchestrer la sync des avis d'un dossier : découverte de la table `Avis`, validation de la structure, upsert ligne par ligne, suppression des orphelins.

**Interface :**
```ruby
syncer = AvisSyncer.new(
  application_tables:,      # Hash { name => table_id } depuis discover_application_tables
  main_table_id:,           # pour valider que Dossier link_row pointe bien vers la table principale
  baserow_config:,          # @baserow_config du SyncCoordinator
  options:,                 # @options
  field_metadata_loader:    # ->(table_id) { @field_filter.load_baserow_fields } pour cache partagé
)

syncer.sync(dossier, main_row_id, file_uploader_proc)
# file_uploader_proc : callable qui prend (data, field_metadata) et fait l'upload des PJ
# (réutilise process_file_uploads du SyncCoordinator via une closure)
```

**Comportement :**
1. Récupère `application_tables['Avis']`. Si nil → log debug + return.
2. Valide la structure : primary `Avis`, link_row `Dossier` pointant vers `main_table_id` avec `link_row_multiple_relationships: false`. Si KO → log warn + return.
3. `AvisFetcher.fetch(dossier.number)` → `avis_list`.
4. `existing_avis_rows = table.find_by_link_row_id('Dossier', main_row_id)`.
5. Pour chaque avis : extract via `DataExtractor.extract_avis_row` (avec PJ existantes de la row Baserow correspondante par ID primary), upload PJ, upsert.
6. Si `supprimer_orphelins` (défaut true) : delete des rows existantes dont `Avis` n'est pas dans la liste actuelle.

- [ ] **Step 4.1 : Écrire le spec en échec**

Créer `spec/lib/mes_demarches_to_baserow/avis_syncer_spec.rb` :

```ruby
# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe MesDemarchesToBaserow::AvisSyncer do
  let(:main_table_id) { 100 }
  let(:avis_table_id) { 200 }
  let(:application_tables) { { 'Avis' => avis_table_id } }

  let(:baserow_config) { { 'table_id' => main_table_id, 'token_config' => nil } }
  let(:options) { {} }

  let(:avis_field_metadata) do
    {
      'Avis' => { 'type' => 'text', 'id' => 1, 'primary' => true },
      'Dossier' => { 'type' => 'link_row', 'id' => 2,
                     'link_row_table_id' => main_table_id,
                     'link_row_table_primary_field' => { 'name' => 'Dossier', 'type' => 'number' } },
      'Question' => { 'type' => 'long_text', 'id' => 3 },
      'Réponse' => { 'type' => 'long_text', 'id' => 4 },
      'Pièces jointes' => { 'type' => 'file', 'id' => 5 }
    }
  end

  let(:field_metadata_loader) { ->(_id) { avis_field_metadata } }
  let(:structure_client) { instance_double(Baserow::StructureClient) }
  let(:avis_table) { instance_double(Baserow::Table) }

  let(:syncer) do
    described_class.new(
      application_tables: application_tables,
      main_table_id: main_table_id,
      baserow_config: baserow_config,
      options: options,
      field_metadata_loader: field_metadata_loader,
      structure_client: structure_client
    )
  end

  let(:dossier) { double('Dossier', number: 12_345) }
  let(:main_row_id) { 42 }
  let(:noop_uploader) { ->(_data, _meta) {} }

  before do
    allow(Baserow::Config).to receive(:table).with(avis_table_id, anything).and_return(avis_table)
    allow(structure_client).to receive(:get_field_by_name).with(avis_table_id, 'Dossier')
                                                          .and_return({ 'type' => 'link_row',
                                                                        'link_row_table_id' => main_table_id,
                                                                        'link_row_multiple_relationships' => false })
    allow(structure_client).to receive(:get_primary_field).with(avis_table_id)
                                                          .and_return({ 'name' => 'Avis', 'type' => 'text' })
  end

  context 'quand la table Avis n\'existe pas dans l\'application' do
    let(:application_tables) { {} }

    it 'skip silencieusement (debug log)' do
      expect(Rails.logger).to receive(:debug).with(/Avis.*absente/)
      expect(MesDemarches::AvisFetcher).not_to receive(:fetch)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'quand la structure de la table Avis est invalide' do
    before do
      allow(structure_client).to receive(:get_primary_field).with(avis_table_id)
                                                            .and_return({ 'name' => 'Mauvais', 'type' => 'text' })
    end

    it 'skip avec un warn explicite' do
      expect(Rails.logger).to receive(:warn).with(/structure invalide/)
      expect(MesDemarches::AvisFetcher).not_to receive(:fetch)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'quand le dossier a 2 avis et 0 row existante' do
    let(:avis1) do
      double('Avis', id: 'AV1', question: 'Q1', reponse: 'R1', question_label: nil, question_answer: nil,
                     date_question: nil, date_reponse: nil,
                     expert: nil, claimant: nil, attachments: [])
    end
    let(:avis2) do
      double('Avis', id: 'AV2', question: 'Q2', reponse: 'R2', question_label: nil, question_answer: nil,
                     date_question: nil, date_reponse: nil,
                     expert: nil, claimant: nil, attachments: [])
    end

    before do
      allow(MesDemarches::AvisFetcher).to receive(:fetch).with(12_345).and_return([avis1, avis2])
      allow(avis_table).to receive(:find_by_link_row_id).with('Dossier', main_row_id).and_return([])
      allow(avis_table).to receive(:create_row).and_return({ 'id' => 1 })
    end

    it 'crée 2 nouvelles rows' do
      expect(avis_table).to receive(:create_row).twice
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'quand un avis existe déjà avec le même ID' do
    let(:avis) do
      double('Avis', id: 'AV1', question: 'Q1 modifiée', reponse: 'R1', question_label: nil, question_answer: nil,
                     date_question: nil, date_reponse: nil,
                     expert: nil, claimant: nil, attachments: [])
    end
    let(:existing_row) { { 'id' => 555, 'Avis' => 'AV1', 'Question' => 'Q1' } }

    before do
      allow(MesDemarches::AvisFetcher).to receive(:fetch).and_return([avis])
      allow(avis_table).to receive(:find_by_link_row_id).and_return([existing_row])
    end

    it 'met à jour la row existante (pas de create)' do
      expect(avis_table).to receive(:update_row).with(555, hash_including('Question' => 'Q1 modifiée'))
      expect(avis_table).not_to receive(:create_row)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'avec supprimer_orphelins activé (défaut)' do
    let(:avis_current) do
      double('Avis', id: 'AV1', question: 'Q', reponse: 'R', question_label: nil, question_answer: nil,
                     date_question: nil, date_reponse: nil,
                     expert: nil, claimant: nil, attachments: [])
    end
    let(:row_kept) { { 'id' => 1, 'Avis' => 'AV1' } }
    let(:row_orphan) { { 'id' => 2, 'Avis' => 'AV_OLD' } }

    before do
      allow(MesDemarches::AvisFetcher).to receive(:fetch).and_return([avis_current])
      allow(avis_table).to receive(:find_by_link_row_id).and_return([row_kept, row_orphan])
      allow(avis_table).to receive(:update_row)
    end

    it 'supprime la row dont l\'ID Avis n\'est plus dans la liste actuelle' do
      expect(avis_table).to receive(:delete_row).with(2)
      expect(avis_table).not_to receive(:delete_row).with(1)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end
end
# rubocop:enable Metrics/BlockLength
```

- [ ] **Step 4.2 : Vérifier l'échec**

```bash
bundle exec rspec spec/lib/mes_demarches_to_baserow/avis_syncer_spec.rb
```

Attendu : `NameError: uninitialized constant MesDemarchesToBaserow::AvisSyncer`.

- [ ] **Step 4.3 : Implémenter `AvisSyncer`**

Créer `app/lib/mes_demarches_to_baserow/avis_syncer.rb` :

```ruby
# frozen_string_literal: true

module MesDemarchesToBaserow
  # Orchestre la synchronisation des avis d'un dossier vers la table Baserow "Avis".
  #
  # Responsabilités:
  # - Découverte de la table "Avis" (skip silencieux si absente)
  # - Validation de la structure minimale (primary "Avis" + link_row "Dossier")
  # - Upsert par ID GraphQL de l'avis (clé stable)
  # - Suppression des avis orphelins (rows Baserow dont l'ID n'est plus présent côté MD)
  class AvisSyncer
    AVIS_TABLE_NAME = 'Avis'
    PRIMARY_FIELD = 'Avis'
    LINK_FIELD = 'Dossier'

    # rubocop:disable Metrics/ParameterLists
    def initialize(application_tables:, main_table_id:, baserow_config:, options:,
                   field_metadata_loader:, structure_client: nil)
      # rubocop:enable Metrics/ParameterLists
      @application_tables = application_tables || {}
      @main_table_id = main_table_id
      @baserow_config = baserow_config
      @options = options || {}
      @field_metadata_loader = field_metadata_loader
      @structure_client = structure_client || Baserow::StructureClient.new
      @avis_field_metadata = nil
    end

    def sync(dossier, main_row_id, file_uploader_proc)
      table_id = @application_tables[AVIS_TABLE_NAME]
      unless table_id
        Rails.logger.debug "BaserowSync.avis: table '#{AVIS_TABLE_NAME}' absente, skip"
        return
      end

      unless valid_structure?(table_id)
        Rails.logger.warn "BaserowSync.avis: structure invalide pour table #{table_id}, skip"
        return
      end

      avis_list = MesDemarches::AvisFetcher.fetch(dossier.number)
      Rails.logger.info "BaserowSync.avis: #{avis_list.length} avis à synchroniser pour dossier #{dossier.number}"

      avis_table = get_table(table_id)
      existing_rows = avis_table.find_by_link_row_id(LINK_FIELD, main_row_id)
      field_metadata = (@avis_field_metadata ||= @field_metadata_loader.call(table_id))
      extractor = DataExtractor.new(field_metadata, @options)

      current_ids = []
      avis_list.each do |avis|
        current_ids << avis.id.to_s
        existing_row = existing_rows.find { |r| r[PRIMARY_FIELD].to_s == avis.id.to_s }
        existing_attachments = existing_row ? Array(existing_row['Pièces jointes']) : []

        row_data = extractor.extract_avis_row(avis, main_row_id, existing_attachments)
        row_data[LINK_FIELD] = [main_row_id] # remplacer la valeur "main_row_id.to_s" par l'array d'IDs

        file_uploader_proc.call(row_data, field_metadata)

        if existing_row
          upserter = RowUpserter.new(avis_table, @options, field_metadata)
          changed = upserter.send(:filter_changed_fields, row_data, existing_row)
          if changed.empty?
            Rails.logger.debug "BaserowSync.avis: avis #{avis.id} inchangé"
          else
            avis_table.update_row(existing_row['id'], changed)
            Rails.logger.info "BaserowSync.avis: avis #{avis.id} mis à jour (#{changed.keys.length} champ(s))"
          end
        else
          avis_table.create_row(row_data)
          Rails.logger.info "BaserowSync.avis: avis #{avis.id} créé"
        end
      end

      delete_orphans(avis_table, existing_rows, current_ids, dossier.number) if supprimer_orphelins?
    end

    private

    def valid_structure?(table_id)
      primary = @structure_client.get_primary_field(table_id)
      return false unless primary && primary['name'] == PRIMARY_FIELD

      link = @structure_client.get_field_by_name(table_id, LINK_FIELD)
      return false unless link && link['type'] == 'link_row'
      return false unless link['link_row_table_id'].to_s == @main_table_id.to_s
      return false if link['link_row_multiple_relationships'] == true

      true
    rescue Baserow::APIError => e
      Rails.logger.error "BaserowSync.avis: erreur validation structure: #{e.message}"
      false
    end

    def delete_orphans(avis_table, existing_rows, current_ids, dossier_number)
      orphans = existing_rows.reject { |r| current_ids.include?(r[PRIMARY_FIELD].to_s) }
      return if orphans.empty?

      orphans.each do |row|
        avis_table.delete_row(row['id'])
        Rails.logger.info "BaserowSync.avis: avis orphelin supprimé (dossier #{dossier_number}, avis #{row[PRIMARY_FIELD]})"
      end
    end

    def supprimer_orphelins?
      @options.key?('supprimer_orphelins') ? @options['supprimer_orphelins'] : true
    end

    def get_table(table_id)
      Baserow::Config.table(table_id, @baserow_config['token_config'])
    end
  end
end
```

- [ ] **Step 4.4 : `require` du nouveau module dans `baserow_sync.rb`**

Dans `app/lib/baserow_sync.rb`, ajouter en tête (parmi les `require_relative`) :

```ruby
require_relative 'mes_demarches/avis_fetcher'
require_relative 'mes_demarches_to_baserow/avis_syncer'
```

- [ ] **Step 4.5 : Vérifier que tous les tests passent**

```bash
bundle exec rspec spec/lib/mes_demarches_to_baserow/avis_syncer_spec.rb
```

Attendu : 5 examples, 0 failures.

- [ ] **Step 4.6 : Lint**

```bash
bundle exec rubocop -A app/lib/mes_demarches_to_baserow/avis_syncer.rb spec/lib/mes_demarches_to_baserow/avis_syncer_spec.rb app/lib/baserow_sync.rb
```

- [ ] **Step 4.7 : Commit**

```bash
git add app/lib/mes_demarches_to_baserow/avis_syncer.rb spec/lib/mes_demarches_to_baserow/avis_syncer_spec.rb app/lib/baserow_sync.rb
git commit -m "feat(baserow_sync): AvisSyncer pour orchestrer sync des avis (upsert + orphelins)"
```

---

### Task 5 : Brancher `AvisSyncer` dans `SyncCoordinator`

**Files:**
- Modify: `app/lib/mes_demarches_to_baserow/sync_coordinator.rb`

**But :** Appeler `AvisSyncer` après `sync_repetable_blocks` dans `sync_dossier`. Passer `process_file_uploads` comme closure pour réutiliser la gestion de fichiers existante.

- [ ] **Step 5.1 : Écrire un test au niveau SyncCoordinator (vérifie l'enchaînement)**

Créer `spec/lib/mes_demarches_to_baserow/sync_coordinator_spec.rb` (s'il n'existe pas) ou ajouter à l'existant :

```ruby
# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe MesDemarchesToBaserow::SyncCoordinator do
  describe '#sync_dossier — étape avis' do
    let(:main_table_id) { 100 }
    let(:baserow_config) { { 'table_id' => main_table_id } }
    let(:options) { {} }

    let(:main_table) { instance_double(Baserow::Table, table_id: main_table_id) }
    let(:upserter) { instance_double(MesDemarchesToBaserow::RowUpserter, upsert_row: 42) }
    let(:client) { instance_double(Baserow::Client) }
    let(:field_filter) { instance_double(MesDemarchesToBaserow::FieldFilter) }
    let(:avis_syncer) { instance_double(MesDemarchesToBaserow::AvisSyncer) }
    let(:dossier) { double('Dossier', number: 12_345, champs: [], annotations: [], demandeur: nil, usager: nil, labels: nil, date_depot: nil, date_passage_en_instruction: nil, date_traitement: nil, state: 'en_instruction') }

    before do
      allow(Baserow::Config).to receive(:table).with(main_table_id, anything).and_return(main_table)
      allow(Baserow::Config).to receive(:client).and_return(client)
      allow(client).to receive(:list_fields).and_return([])
      allow(MesDemarchesToBaserow::FieldFilter).to receive(:new).and_return(field_filter)
      allow(field_filter).to receive(:filter_syncable_fields) { |data| data }
      allow(main_table).to receive(:find_by_normalized).and_return([])
      allow(MesDemarchesToBaserow::RowUpserter).to receive(:new).and_return(upserter)
      allow(MesDemarchesToBaserow::AvisSyncer).to receive(:new).and_return(avis_syncer)
      allow(avis_syncer).to receive(:sync)
    end

    it 'appelle AvisSyncer#sync avec le dossier et main_row_id' do
      coordinator = described_class.new(main_table_id, baserow_config, options)
      coordinator.sync_dossier(dossier)

      expect(avis_syncer).to have_received(:sync).with(dossier, 42, kind_of(Proc))
    end
  end
end
# rubocop:enable Metrics/BlockLength
```

- [ ] **Step 5.2 : Vérifier l'échec**

```bash
bundle exec rspec spec/lib/mes_demarches_to_baserow/sync_coordinator_spec.rb
```

Attendu : FAIL — `AvisSyncer.new` n'est jamais appelé.

- [ ] **Step 5.3 : Modifier `SyncCoordinator#sync_dossier`**

Dans `app/lib/mes_demarches_to_baserow/sync_coordinator.rb`, après la ligne `sync_repetable_blocks(...)` (ligne ~72), ajouter :

```ruby
      # 7b. Synchroniser les avis du dossier vers la table "Avis" (auto-découverte)
      sync_avis(dossier, main_row_id)
```

Puis ajouter la méthode privée :

```ruby
    def sync_avis(dossier, main_row_id)
      return unless main_row_id

      available_tables = discover_application_tables
      syncer = AvisSyncer.new(
        application_tables: available_tables,
        main_table_id: @baserow_config['table_id'],
        baserow_config: @baserow_config,
        options: @options,
        field_metadata_loader: ->(table_id) { load_block_field_metadata(table_id) }
      )

      file_uploader_proc = ->(data, field_metadata) { process_file_uploads(data, field_metadata) }
      syncer.sync(dossier, main_row_id, file_uploader_proc)
    rescue StandardError => e
      Rails.logger.error "BaserowSync.avis: erreur sync avis (dossier #{dossier.number}): #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
```

- [ ] **Step 5.4 : Vérifier les tests SyncCoordinator**

```bash
bundle exec rspec spec/lib/mes_demarches_to_baserow/sync_coordinator_spec.rb
```

Attendu : test passe.

- [ ] **Step 5.5 : Smoke test global**

```bash
bundle exec rspec spec/lib/baserow_sync_spec.rb spec/lib/mes_demarches_to_baserow/
```

Attendu : aucune régression sur les tests existants.

- [ ] **Step 5.6 : Lint**

```bash
bundle exec rubocop -A app/lib/mes_demarches_to_baserow/sync_coordinator.rb spec/lib/mes_demarches_to_baserow/sync_coordinator_spec.rb
```

- [ ] **Step 5.7 : Commit**

```bash
git add app/lib/mes_demarches_to_baserow/sync_coordinator.rb spec/lib/mes_demarches_to_baserow/sync_coordinator_spec.rb
git commit -m "feat(baserow_sync): brancher AvisSyncer dans SyncCoordinator"
```

---

### Task 6 : Test end-to-end sync (WebMock)

**Files:**
- Modify: `spec/lib/baserow_sync_spec.rb` (ajout d'un nouveau context)

**But :** Valider en bout en bout qu'un dossier avec 2 avis dont 1 a 2 PJ produit 2 rows dans la table `Avis`, avec PJ uploadées.

- [ ] **Step 6.1 : Écrire le test end-to-end**

Ajouter dans `spec/lib/baserow_sync_spec.rb` un nouveau context. Le pattern dépend de comment les tests existants sont structurés ; si WebMock est déjà utilisé, suivre le même schéma. Sinon, utiliser des mocks directs sur `Baserow::Config.table` et `MesDemarches::AvisFetcher`. Exemple **avec mocks** (à adapter si le fichier existe déjà avec WebMock) :

```ruby
  describe 'synchronisation des avis' do
    let(:demarche) { double('Demarche', id: 999) }
    let(:dossier) { double('Dossier', number: 12_345, champs: [], annotations: [], demandeur: nil, usager: nil, labels: nil, date_depot: nil, date_passage_en_instruction: nil, date_traitement: nil, state: 'en_instruction') }

    let(:main_table) { instance_double(Baserow::Table, table_id: 100) }
    let(:avis_table) { instance_double(Baserow::Table, table_id: 200) }
    let(:upserter) { instance_double(MesDemarchesToBaserow::RowUpserter, upsert_row: 42) }
    let(:structure_client) { instance_double(Baserow::StructureClient) }
    let(:client) { instance_double(Baserow::Client) }

    let(:avis_with_attachments) do
      double('Avis',
             id: 'AV1', question: 'Avis service A',
             reponse: 'Favorable',
             question_label: nil, question_answer: nil,
             date_question: nil, date_reponse: nil,
             expert: nil, claimant: nil,
             attachments: [double('File', filename: 'avis.pdf', url: 'https://md.gp.pf/avis.pdf', byte_size: 1000)])
    end

    let(:avis_without_attachments) do
      double('Avis',
             id: 'AV2', question: 'Avis service B', reponse: nil,
             question_label: nil, question_answer: nil,
             date_question: nil, date_reponse: nil,
             expert: nil, claimant: nil, attachments: [])
    end

    before do
      allow(Baserow::Config).to receive(:table).with(100, anything).and_return(main_table)
      allow(Baserow::Config).to receive(:table).with(200, anything).and_return(avis_table)
      allow(Baserow::Config).to receive(:client).and_return(client)
      allow(client).to receive(:list_fields).and_return([])

      allow(main_table).to receive(:find_by_normalized).and_return([])
      allow(MesDemarchesToBaserow::RowUpserter).to receive(:new).and_return(upserter)

      # Discovery
      allow(Baserow::StructureClient).to receive(:new).and_return(structure_client)
      allow(structure_client).to receive(:get_table).with(100).and_return({ 'database_id' => 1 })
      allow(structure_client).to receive(:list_tables).with(1).and_return([
                                                                           { 'id' => 200, 'name' => 'Avis' }
                                                                         ])
      # Validation structure Avis
      allow(structure_client).to receive(:get_primary_field).with(200).and_return({ 'name' => 'Avis', 'type' => 'text' })
      allow(structure_client).to receive(:get_field_by_name).with(200, 'Dossier')
                                                            .and_return({ 'type' => 'link_row',
                                                                          'link_row_table_id' => 100,
                                                                          'link_row_multiple_relationships' => false })
      # Field metadata pour table Avis
      avis_meta = {
        'Avis' => { 'type' => 'text', 'id' => 1, 'primary' => true },
        'Dossier' => { 'type' => 'link_row', 'id' => 2 },
        'Question' => { 'type' => 'long_text', 'id' => 3 },
        'Réponse' => { 'type' => 'long_text', 'id' => 4 },
        'Pièces jointes' => { 'type' => 'file', 'id' => 5 }
      }
      allow_any_instance_of(MesDemarchesToBaserow::FieldFilter).to receive(:load_baserow_fields).and_return(avis_meta)

      allow(avis_table).to receive(:find_by_link_row_id).and_return([])
      allow(avis_table).to receive(:create_row).and_return({ 'id' => 0 })

      # Fetch avis
      allow(MesDemarches::AvisFetcher).to receive(:fetch).with(12_345)
                                                        .and_return([avis_with_attachments, avis_without_attachments])

      # File uploader (no-op pour ce test)
      allow_any_instance_of(Baserow::FileUploader).to receive(:download_and_upload)
        .and_return({ 'name' => 'uploaded_hash', 'visible_name' => 'avis.pdf' })
    end

    it 'crée 2 rows dans la table Avis (1 avec PJ uploadée, 1 sans PJ)' do
      params = { baserow: { 'table_id' => 100 } }
      checker = BaserowSync.new(params)
      checker.process(demarche, dossier)

      expect(avis_table).to have_received(:create_row).twice
      expect(avis_table).to have_received(:create_row).with(hash_including('Question' => 'Avis service A'))
      expect(avis_table).to have_received(:create_row).with(hash_including('Question' => 'Avis service B'))
    end
  end
```

- [ ] **Step 6.2 : Lancer**

```bash
bundle exec rspec spec/lib/baserow_sync_spec.rb
```

Attendu : tous les examples passent (anciens + 1 nouveau pour avis).

- [ ] **Step 6.3 : Commit**

```bash
git add spec/lib/baserow_sync_spec.rb
git commit -m "test(baserow_sync): end-to-end sync de 2 avis avec et sans PJ"
```

---

## Phase 2 — Builder + Admin UI

### Task 7 : `AvisTableBuilder`

**Files:**
- Create: `app/lib/mes_demarches_to_baserow/avis_table_builder.rb`
- Create: `spec/lib/mes_demarches_to_baserow/avis_table_builder_spec.rb`

**But :** Création idempotente de la table `Avis` dans l'application Baserow, avec primary `Avis` (text), link_row `Dossier`, et toutes les colonnes standard. Ne touche jamais aux colonnes existantes.

**Interface :**
```ruby
builder = MesDemarchesToBaserow::AvisTableBuilder.new(main_table_id, application_id, workspace_id)
builder.preview  # => { will_create_table:, table_name:, existing_fields:, missing_fields: }
builder.build!   # => { table_created:, fields_created:, errors: }
```

**Schéma des colonnes standard :**

| Nom | Config Baserow |
|---|---|
| `Avis` (primary) | `{ type: 'text', name: 'Avis' }` (primary par défaut à la création de table) |
| `Dossier` | `{ type: 'link_row', name: 'Dossier', link_row_table_id: main_table_id, has_related_field: true, link_row_multiple_relationships: false }` |
| `Question` | `{ type: 'long_text', name: 'Question' }` |
| `Réponse` | `{ type: 'long_text', name: 'Réponse' }` |
| `Libellé question` | `{ type: 'text', name: 'Libellé question' }` |
| `Réponse fermée` | `{ type: 'boolean', name: 'Réponse fermée' }` |
| `Date question` | `{ type: 'date', name: 'Date question' }` |
| `Date réponse` | `{ type: 'date', name: 'Date réponse' }` |
| `Email expert` | `{ type: 'email', name: 'Email expert' }` |
| `Email demandeur` | `{ type: 'email', name: 'Email demandeur' }` |
| `Pièces jointes` | `{ type: 'file', name: 'Pièces jointes' }` |

- [ ] **Step 7.1 : Écrire le spec en échec**

Créer `spec/lib/mes_demarches_to_baserow/avis_table_builder_spec.rb` :

```ruby
# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe MesDemarchesToBaserow::AvisTableBuilder do
  let(:main_table_id) { 100 }
  let(:application_id) { 1 }
  let(:workspace_id) { 1 }
  let(:structure_client) { instance_double(Baserow::StructureClient) }

  let(:builder) do
    described_class.new(main_table_id, application_id, workspace_id, structure_client: structure_client)
  end

  before do
    allow(structure_client).to receive(:get_table).with(main_table_id).and_return({ 'id' => 100 })
    allow(structure_client).to receive(:field_exists?).with(main_table_id, 'Dossier').and_return(true)
  end

  describe '#preview' do
    context 'quand la table Avis n\'existe pas' do
      before do
        allow(structure_client).to receive(:list_applications).with(workspace_id)
                                                              .and_return([{ 'id' => application_id, 'tables' => [] }])
      end

      it 'indique que la table sera créée avec toutes les colonnes manquantes' do
        result = builder.preview
        expect(result[:will_create_table]).to be true
        expect(result[:missing_fields]).to include('Avis', 'Dossier', 'Question', 'Réponse', 'Pièces jointes')
      end
    end

    context 'quand la table Avis existe avec quelques colonnes' do
      before do
        allow(structure_client).to receive(:list_applications).with(workspace_id)
                                                              .and_return([{ 'id' => application_id,
                                                                             'tables' => [{ 'id' => 200, 'name' => 'Avis' }] }])
        allow(structure_client).to receive(:get_table_fields).with(200)
                                                             .and_return([
                                                                           { 'name' => 'Avis', 'type' => 'text', 'primary' => true },
                                                                           { 'name' => 'Dossier', 'type' => 'link_row' },
                                                                           { 'name' => 'Question', 'type' => 'long_text' }
                                                                         ])
      end

      it 'liste les colonnes manquantes' do
        result = builder.preview
        expect(result[:will_create_table]).to be false
        expect(result[:existing_fields]).to include('Avis', 'Dossier', 'Question')
        expect(result[:missing_fields]).to include('Réponse', 'Pièces jointes')
        expect(result[:missing_fields]).not_to include('Question')
      end
    end
  end

  describe '#build!' do
    context 'quand la table Avis n\'existe pas' do
      before do
        allow(structure_client).to receive(:list_applications).with(workspace_id)
                                                              .and_return([{ 'id' => application_id, 'tables' => [] }])
        allow(structure_client).to receive(:create_table)
          .and_return({ 'id' => 200, 'name' => 'Avis' })
        allow(structure_client).to receive(:get_table_fields).with(200).and_return([
                                                                                     { 'name' => 'Name', 'type' => 'text', 'primary' => true, 'id' => 999 }
                                                                                   ])
        allow(structure_client).to receive(:update_field).and_return({})
        allow(structure_client).to receive(:create_field).and_return({})
        allow(structure_client).to receive(:get_field_by_name).and_return(nil)
      end

      it 'crée la table puis toutes les colonnes standard' do
        result = builder.build!

        expect(result[:table_created]).to be true
        expect(result[:fields_created]).to include('Dossier', 'Question', 'Réponse', 'Pièces jointes')
        expect(structure_client).to have_received(:create_table).once
      end
    end

    context 'quand la table Avis existe avec structure partielle' do
      before do
        allow(structure_client).to receive(:list_applications).with(workspace_id)
                                                              .and_return([{ 'id' => application_id,
                                                                             'tables' => [{ 'id' => 200, 'name' => 'Avis' }] }])
        allow(structure_client).to receive(:get_table_fields).with(200)
                                                             .and_return([
                                                                           { 'name' => 'Avis', 'type' => 'text', 'primary' => true },
                                                                           { 'name' => 'Question', 'type' => 'long_text' }
                                                                         ])
        allow(structure_client).to receive(:get_field_by_name).with(200, 'Dossier').and_return(nil)
        allow(structure_client).to receive(:create_field).and_return({})
      end

      it 'crée uniquement les colonnes manquantes (ne touche pas Question)' do
        result = builder.build!

        expect(result[:table_created]).to be false
        expect(result[:fields_created]).not_to include('Question')
        expect(result[:fields_created]).to include('Dossier', 'Réponse', 'Pièces jointes')
      end
    end

    context 'quand le link_row Dossier existe mais avec multiple_relationships=true' do
      before do
        allow(structure_client).to receive(:list_applications).with(workspace_id)
                                                              .and_return([{ 'id' => application_id,
                                                                             'tables' => [{ 'id' => 200, 'name' => 'Avis' }] }])
        allow(structure_client).to receive(:get_table_fields).with(200)
                                                             .and_return([{ 'name' => 'Avis', 'type' => 'text', 'primary' => true }])
        allow(structure_client).to receive(:get_field_by_name).with(200, 'Dossier')
                                                              .and_return({ 'id' => 50, 'type' => 'link_row',
                                                                            'link_row_multiple_relationships' => true })
        allow(structure_client).to receive(:update_field).and_return({})
        allow(structure_client).to receive(:create_field).and_return({})
      end

      it 'corrige la configuration vers single relationship' do
        builder.build!
        expect(structure_client).to have_received(:update_field).with(50, hash_including(link_row_multiple_relationships: false))
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
```

- [ ] **Step 7.2 : Vérifier l'échec**

```bash
bundle exec rspec spec/lib/mes_demarches_to_baserow/avis_table_builder_spec.rb
```

Attendu : `NameError: uninitialized constant`.

- [ ] **Step 7.3 : Implémenter `AvisTableBuilder`**

Créer `app/lib/mes_demarches_to_baserow/avis_table_builder.rb` :

```ruby
# frozen_string_literal: true

module MesDemarchesToBaserow
  # Crée/met à jour de façon idempotente la table Baserow "Avis" associée
  # à une démarche, conformément au design baserow_sync-avis.
  #
  # Ne supprime jamais de colonnes existantes.
  class AvisTableBuilder
    class BuilderError < StandardError; end

    TABLE_NAME = 'Avis'

    # Colonnes standard créées si absentes.
    # Ordre = ordre de création. "Dossier" est traité à part (validation/maj).
    STANDARD_FIELDS = [
      { name: 'Question', config: { type: 'long_text' } },
      { name: 'Réponse', config: { type: 'long_text' } },
      { name: 'Libellé question', config: { type: 'text' } },
      { name: 'Réponse fermée', config: { type: 'boolean' } },
      { name: 'Date question', config: { type: 'date' } },
      { name: 'Date réponse', config: { type: 'date' } },
      { name: 'Email expert', config: { type: 'email' } },
      { name: 'Email demandeur', config: { type: 'email' } },
      { name: 'Pièces jointes', config: { type: 'file' } }
    ].freeze

    attr_reader :report

    def initialize(main_table_id, application_id, workspace_id, structure_client: nil)
      @main_table_id = main_table_id
      @application_id = application_id
      @workspace_id = workspace_id
      @structure_client = structure_client || Baserow::StructureClient.new
      @report = { table_created: false, fields_created: [], errors: [] }
    end

    def preview
      validate_main_table!
      existing = find_existing_table
      if existing.nil?
        {
          will_create_table: true,
          table_name: TABLE_NAME,
          existing_fields: [],
          missing_fields: ['Avis', 'Dossier'] + STANDARD_FIELDS.map { |f| f[:name] }
        }
      else
        existing_field_names = @structure_client.get_table_fields(existing['id']).map { |f| f['name'] }
        all_targets = ['Avis', 'Dossier'] + STANDARD_FIELDS.map { |f| f[:name] }
        {
          will_create_table: false,
          table_name: TABLE_NAME,
          existing_fields: existing_field_names,
          missing_fields: all_targets - existing_field_names
        }
      end
    end

    def build!
      validate_main_table!
      table = find_existing_table
      table_id = table ? table['id'] : create_avis_table

      ensure_dossier_link_row(table_id)
      ensure_standard_fields(table_id)

      @report
    rescue StandardError => e
      Rails.logger.error "AvisTableBuilder: #{e.message}"
      @report[:errors] << e.message
      @report
    end

    private

    def validate_main_table!
      raise BuilderError, "Table principale #{@main_table_id} introuvable" unless @structure_client.get_table(@main_table_id)
      raise BuilderError, 'La table principale doit avoir un champ "Dossier"' unless @structure_client.field_exists?(@main_table_id, 'Dossier')
    end

    def find_existing_table
      applications = @structure_client.list_applications(@workspace_id)
      application = applications.find { |app| app['id'].to_s == @application_id.to_s }
      return nil unless application

      (application['tables'] || []).find { |t| t['name'] == TABLE_NAME }
    end

    def create_avis_table
      new_table = @structure_client.create_table(@application_id, { name: TABLE_NAME })
      @report[:table_created] = true

      # Renommer le champ primaire par défaut en "Avis" (text)
      fields = @structure_client.get_table_fields(new_table['id'])
      primary = fields.find { |f| f['primary'] }
      @structure_client.update_field(primary['id'], { name: 'Avis', type: 'text' }) if primary && primary['name'] != 'Avis'

      new_table['id']
    end

    def ensure_dossier_link_row(table_id)
      existing = @structure_client.get_field_by_name(table_id, 'Dossier')
      if existing
        if existing['type'] == 'link_row' && existing['link_row_multiple_relationships'] == true
          @structure_client.update_field(existing['id'], { link_row_multiple_relationships: false })
        end
        return
      end

      @structure_client.create_field(table_id, {
                                       type: 'link_row',
                                       name: 'Dossier',
                                       link_row_table_id: @main_table_id,
                                       has_related_field: true,
                                       link_row_multiple_relationships: false
                                     })
      @report[:fields_created] << 'Dossier'
    end

    def ensure_standard_fields(table_id)
      existing_names = @structure_client.get_table_fields(table_id).map { |f| f['name'] }
      STANDARD_FIELDS.each do |field|
        next if existing_names.include?(field[:name])

        @structure_client.create_field(table_id, field[:config].merge(name: field[:name]))
        @report[:fields_created] << field[:name]
      end
    end
  end
end
```

- [ ] **Step 7.4 : `require` dans `baserow_sync.rb`**

Ajouter dans `app/lib/baserow_sync.rb` (en haut, avec les autres `require_relative`) :

```ruby
require_relative 'mes_demarches_to_baserow/avis_table_builder'
```

- [ ] **Step 7.5 : Vérifier les tests**

```bash
bundle exec rspec spec/lib/mes_demarches_to_baserow/avis_table_builder_spec.rb
```

Attendu : 4 examples, 0 failures.

- [ ] **Step 7.6 : Lint**

```bash
bundle exec rubocop -A app/lib/mes_demarches_to_baserow/avis_table_builder.rb spec/lib/mes_demarches_to_baserow/avis_table_builder_spec.rb app/lib/baserow_sync.rb
```

- [ ] **Step 7.7 : Commit**

```bash
git add app/lib/mes_demarches_to_baserow/avis_table_builder.rb spec/lib/mes_demarches_to_baserow/avis_table_builder_spec.rb app/lib/baserow_sync.rb
git commit -m "feat(baserow_sync): AvisTableBuilder pour création/maj idempotente de la table Avis"
```

---

### Task 8 : Actions admin `preview_avis_table` et `build_avis_table`

**Files:**
- Modify: `app/controllers/admin/baserow_schema_controller.rb`
- Modify: `config/routes.rb` (ajout des deux routes admin)

**But :** Exposer le builder via deux actions admin qui suivent le pattern `preview_repetable_blocks` / `build_repetable_blocks`.

- [ ] **Step 8.1 : Inspecter les routes existantes**

```bash
grep -n "baserow_schema\|repetable" config/routes.rb
```

Repérer où sont définies les routes `preview_repetable_blocks` et `build_repetable_blocks` pour ajouter les nôtres au même endroit.

- [ ] **Step 8.2 : Ajouter les routes**

Dans `config/routes.rb`, à côté des routes `preview_repetable_blocks` et `build_repetable_blocks` existantes, ajouter :

```ruby
        post 'baserow_schema/preview_avis_table', to: 'baserow_schema#preview_avis_table', as: :preview_avis_table
        post 'baserow_schema/build_avis_table',   to: 'baserow_schema#build_avis_table',   as: :build_avis_table
```

(Adapter le format à celui des routes existantes — `get` ou `post`, sous `namespace :admin do`, etc.)

- [ ] **Step 8.3 : Ajouter les actions au controller**

Dans `app/controllers/admin/baserow_schema_controller.rb`, à côté de `preview_repetable_blocks` et `build_repetable_blocks` (vers la ligne 168-185), ajouter :

```ruby
    def preview_avis_table
      params_hash = extract_avis_params
      preview_avis_with_params(params_hash)
    end

    def build_avis_table
      params_hash = extract_avis_params
      build_avis_with_params(params_hash)
    end
```

Puis ajouter dans la partie `private` :

```ruby
    def extract_avis_params
      {
        main_table_id: params.require(:main_table_id),
        application_id: params.require(:application_id),
        workspace_id: params.require(:workspace_id)
      }
    end

    def preview_avis_with_params(params_hash)
      builder = MesDemarchesToBaserow::AvisTableBuilder.new(
        params_hash[:main_table_id],
        params_hash[:application_id],
        params_hash[:workspace_id]
      )
      preview = builder.preview
      render json: preview
    rescue MesDemarchesToBaserow::AvisTableBuilder::BuilderError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def build_avis_with_params(params_hash)
      builder = MesDemarchesToBaserow::AvisTableBuilder.new(
        params_hash[:main_table_id],
        params_hash[:application_id],
        params_hash[:workspace_id]
      )
      report = builder.build!
      render json: report
    rescue MesDemarchesToBaserow::AvisTableBuilder::BuilderError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
```

- [ ] **Step 8.4 : Smoke test (controller charge en console)**

```bash
bundle exec rails runner "puts Admin::BaserowSchemaController.instance_methods(false).inspect"
```

Attendu : la sortie inclut `:preview_avis_table` et `:build_avis_table`.

- [ ] **Step 8.5 : Lint**

```bash
bundle exec rubocop -A app/controllers/admin/baserow_schema_controller.rb config/routes.rb
```

- [ ] **Step 8.6 : Commit**

```bash
git add app/controllers/admin/baserow_schema_controller.rb config/routes.rb
git commit -m "feat(baserow_sync): actions admin pour preview/build de la table Avis"
```

---

### Task 9 : UI admin — section « Table Avis »

**Files:**
- Modify: `app/views/admin/baserow_schema/repetable_blocks.html.haml`

**But :** Ajouter une section dans la vue existante avec un bouton « Aperçu table Avis » et « Créer/mettre à jour table Avis » utilisant les deux nouvelles actions.

- [ ] **Step 9.1 : Inspecter la vue existante**

```bash
cat /home/clautier/Rubymine/inspecteur-mes-demarches/app/views/admin/baserow_schema/repetable_blocks.html.haml | head -50
```

Repérer comment les boutons « preview / build » des blocs répétables sont structurés (formulaires, JS, helpers).

- [ ] **Step 9.2 : Ajouter la section Avis**

Dans `app/views/admin/baserow_schema/repetable_blocks.html.haml`, à un endroit cohérent (après la section blocs répétables), ajouter une section HAML. Modèle à adapter au style du fichier existant :

```haml
%hr
%section.avis-table-section
  %h2 Table « Avis »
  %p
    Crée ou met à jour la table Baserow « Avis » liée à la table principale via un link_row.
    Sera utilisée par la synchronisation automatique des avis (avec pièces jointes).

  = form_with url: preview_avis_table_admin_baserow_schema_path, method: :post, local: false, id: 'preview-avis-table-form' do |f|
    = f.hidden_field :main_table_id
    = f.hidden_field :application_id
    = f.hidden_field :workspace_id
    = f.submit 'Aperçu table Avis', class: 'btn btn-secondary'

  = form_with url: build_avis_table_admin_baserow_schema_path, method: :post, local: false, id: 'build-avis-table-form' do |f|
    = f.hidden_field :main_table_id
    = f.hidden_field :application_id
    = f.hidden_field :workspace_id
    = f.submit 'Créer/mettre à jour table Avis', class: 'btn btn-primary', data: { confirm: 'Confirmer la création/maj de la table Avis ?' }

  #avis-table-result
```

**Note :** Les hidden_fields doivent être pré-remplis avec les valeurs du contexte (probablement via `params` ou variables d'instance que la vue existante utilise déjà — calquer sur la section blocs répétables).

- [ ] **Step 9.3 : Test manuel (browser)**

Lancer le serveur :

```bash
bin/dev
```

Naviguer vers `/admin/baserow_schema/repetable_blocks?...` (avec les params nécessaires comme pour les blocs), vérifier que la nouvelle section apparaît et que les boutons sont fonctionnels.

**Si pas d'environnement local pour le test browser :** au minimum, vérifier que la vue ne plante pas en compilant un cas simple :

```bash
bundle exec rails runner "puts ActionController::Base.new.render_to_string(template: 'admin/baserow_schema/repetable_blocks', locals: {}).length"
```

(Adapter selon les variables exigées par la vue.)

- [ ] **Step 9.4 : Lint**

```bash
bundle exec rake lint
```

- [ ] **Step 9.5 : Commit**

```bash
git add app/views/admin/baserow_schema/repetable_blocks.html.haml
git commit -m "feat(baserow_sync): UI admin pour preview/build de la table Avis"
```

---

## Phase 3 — Documentation

### Task 10 : Mise à jour de la documentation

**Files:**
- Modify: `app/lib/mes_demarches_to_baserow/README.md`

**But :** Documenter la sync des avis (data flow, structure de table, builder, edge cases) pour les futurs utilisateurs.

- [ ] **Step 10.1 : Ajouter une section "Synchronisation des avis"**

Ajouter à la fin de `app/lib/mes_demarches_to_baserow/README.md` (avant la section "Tests" finale) :

```markdown
## Synchronisation des avis

Les avis d'un dossier (consultations expert) sont synchronisés vers une table Baserow dédiée `Avis`, liée à la table principale via un link_row.

### Cas d'usage type

Démarches de permis de construire où plusieurs services administratifs sont consultés. Chaque avis contient une réponse texte courte et souvent une PJ détaillée (avis en PDF). L'application Baserow donne accès aux deux.

### Structure attendue de la table « Avis »

| Colonne | Type Baserow | Source MD |
|---|---|---|
| `Avis` (primary) | text | `avis.id` (ID GraphQL) |
| `Dossier` | link_row → table principale (multiple_relationships: false) | `existing_row.id` |
| `Question` | long_text | `avis.question` |
| `Réponse` | long_text | `avis.reponse` |
| `Libellé question` | text | `avis.questionLabel` |
| `Réponse fermée` | boolean | `avis.questionAnswer` |
| `Date question` | date | `avis.dateQuestion` |
| `Date réponse` | date | `avis.dateReponse` |
| `Email expert` | email | `avis.expert.email` |
| `Email demandeur` | email | `avis.claimant.email` |
| `Pièces jointes` | file | `avis.attachments` |

Toutes les colonnes sont optionnelles sauf `Avis` (primary) et `Dossier` (link_row). La sync remplit ce qui existe.

### Création de la table

Via l'UI admin (`/admin/baserow_schema/repetable_blocks`), section « Table Avis ». Boutons « Aperçu » et « Créer/mettre à jour ». Le builder est idempotent : il ne supprime jamais rien.

### Fonctionnement de la sync

1. Découverte : si la table `Avis` n'existe pas dans l'application, skip silencieux.
2. Validation de la structure (primary `Avis` + link_row `Dossier`). Si KO, skip avec warn.
3. Fetch des avis du dossier via GraphQL (incluant `attachments`).
4. Pour chaque avis, upsert par ID GraphQL.
5. PJ : réutilisation de la déduplication par nom+taille (idem PJ des champs).
6. Suppression des avis orphelins (présents en Baserow mais plus en MD) si `supprimer_orphelins: true` (défaut).
```

- [ ] **Step 10.2 : Commit**

```bash
git add app/lib/mes_demarches_to_baserow/README.md
git commit -m "docs(baserow_sync): documenter la synchronisation des avis"
```

---

## Validation finale

- [ ] **Step F.1 : Suite complète des tests**

```bash
bundle exec rspec spec/lib/baserow_sync_spec.rb spec/lib/baserow/ spec/lib/mes_demarches/ spec/lib/mes_demarches_to_baserow/
```

Attendu : 0 failure, aucune régression.

- [ ] **Step F.2 : Lint global**

```bash
bundle exec rake lint
```

- [ ] **Step F.3 : Vérifier les commits**

```bash
git log --oneline dev ^origin/dev
```

Attendu : ~10 commits propres, lisibles, un par task.

---

## Notes pour l'implémenteur

- **TDD strict** : chaque task suit le pattern test → fail → implem → pass → commit. Ne pas implémenter avant d'avoir un test rouge.
- **Pas de placeholder** : si une étape mentionne une « adaptation au style du fichier existant », c'est attendu (le HAML existant impose son style). Ne pas inventer un style à part.
- **Mocks GraphQL** : tous les avis sont des `double` Ruby. Aucun appel réseau réel dans les tests.
- **Mocks Baserow** : `Baserow::Config.table`, `Baserow::StructureClient.new` sont mockés via `allow`. Pas d'appel API réel.
- **Le file uploader est passé comme closure** depuis SyncCoordinator : ça évite à `AvisSyncer` de connaître les détails d'upload (download_and_upload, etc.).
- **Si une étape échoue de façon inattendue**, ne pas inventer une autre approche : poser la question à l'utilisateur.
- **`process_file_uploads` lit `@failed_uploads`** dans `SyncCoordinator`. La closure capture l'instance, donc les failed uploads des avis sont remontés via le `raise` final de `sync_dossier` (comportement existant).
