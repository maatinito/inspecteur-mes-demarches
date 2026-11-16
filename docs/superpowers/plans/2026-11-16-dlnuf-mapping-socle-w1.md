# Mapping déclaratif vers la table socle (lot W1) — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** permettre à `baserow_sync` d'alimenter une table aux colonnes communes (table socle Financeurs 1046) depuis des démarches aux libellés divergents, grâce à un bloc `mapping:` dont chaque valeur est soit un `stable_id`, soit un gabarit.

**Architecture :** un objet `MesDemarchesToBaserow::Mapping`, construit une fois par passe dans le `SyncCoordinator`, confronte la configuration à la table Baserow et à la révision de la démarche, journalise ses avertissements une seule fois et ne garde que les entrées valides. Quand un `mapping:` est déclaré, le `DataExtractor` passe en mode exclusif : métadonnées système par nom + colonnes du mapping, plus aucun appariement par libellé (ni annotations, ni sous-colonnes, ni blocs). Les gabarits sont instanciés par `FieldChecker#instanciate`, passé au coordinateur sous forme de lambda par `BaserowSync`.

**Tech Stack :** Rails, RSpec, Baserow REST, GraphQL Mes-Démarches (`MesDemarches::Queries::DemarcheRevision`).

**Spec :** `docs/superpowers/specs/2026-07-22-devis-dlnuf-subventions-global.md` §2.2 et ligne W1 (révision du 16/11/2026). Contexte DLNUF déjà livré : `docs/superpowers/plans/2026-11-13-dlnuf-contrat-baserow.md`, `app/lib/mes_demarches_to_baserow/README.md` § « Référentiel DLNUF ».

## Global Constraints

- Branche `dlnuf-mapping` partie de `dlnuf-contrat` (non encore fusionnée dans `dev` au 16/11 : 2659a73), dans un worktree séparé `../imd-dlnuf-mapping` pour ne pas gêner la session qui travaille sur `dlnuf-contrat` ; rebaser sur `dev` une fois `dlnuf-contrat` fusionnée. Jamais de push direct sur `master`.
- Avant chaque commit : `bundle exec rubocop -A` puis `bundle exec rake lint` (CLAUDE.md).
- **Sans `mapping:`, comportement strictement inchangé** : toutes les specs existantes de `spec/lib/mes_demarches_to_baserow` restent vertes sans modifier leurs attentes.
- Ne pas incrémenter `BaserowSync#version`.
- Sous-hash YAML : clés chaînes (`@params[:mapping]` est un Hash `{ 'Colonne' => valeur }`).
- Forme d'une valeur : `Integer` = `stable_id` ; `String` = gabarit (sans accolade = constante). Toute autre forme = erreur de configuration (`@errors`).
- Types de colonne admis pour un gabarit : `text long_text single_select email url`. Tous les autres (`file date number phone_number boolean multiple_select link_row`…) n'acceptent qu'un `stable_id`.
- Garde-fous **non destructifs** : avertissement journalisé (`Rails.logger.warn`, préfixe `BaserowSync mapping:`), entrée ignorée, aucune écriture dans la colonne, aucun blocage. Liste exacte :
  1. colonne absente de la table ;
  2. gabarit sur une colonne d'un type non admis ;
  3. `stable_id` inconnu des révisions (brouillon ∪ publiée) de la démarche ;
  4. `stable_id` qui désigne une annotation privée (le socle = champs usager seulement) ;
  5. libellé `{…}` d'un gabarit inconnu des révisions (champs ∪ annotations) ;
  6. chaîne faite uniquement de chiffres (`"140066"`) : avertissement « stable_id attendu ? », mais l'entrée est **gardée** comme constante.
- Champ dont le `stable_id` est connu de la révision mais absent du dossier (masqué par une condition, ou ajouté après le dépôt) : valeur `nil` → cellule vidée. C'est une absence légitime, pas un avertissement.
- Gabarit qui s'instancie en `''` : écrire `nil`.
- Pièce jointe mappée en DLNUF : référence `md:<numero>:<stable_id>` via le chemin existant (`extract_reference_pj`), colonne marquée `reference=piece_justificative` obligatoire (sinon l'avertissement existant).

## Review Focus

1. **Champ masqué par une condition** (stable_id connu, absent du dossier) → cellule vidée, aucun avertissement. Test en tâche 2.
2. **Métadonnées système avec mapping** : « Raison sociale », « Numéro TAHITI », « Date de dépôt » et la colonne propriétaire restent écrites alors que l'appariement par libellé est coupé. Test en tâche 2.
3. **Un champ du formulaire homonyme d'une colonne socle non mappée** (ex. champ « Statuts » chez un service, colonne « Statuts » non déclarée) → pas écrit. Test en tâche 2.
4. **Constante sur une colonne `single_select`** (« Service: DIREN ») → acceptée par le Mapping (type admis). Test en tâche 1.
5. **Avertissements journalisés une fois par passe**, pas une fois par dossier (le Mapping est construit dans le constructeur du coordinateur). Test en tâche 3.

---

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `app/lib/mes_demarches_to_baserow/mapping.rb` (créer) | Validation statique (config) et contextuelle (table + révision), entrées retenues |
| `app/lib/referentiel/reference_pj.rb` (modifier) | Exposer `stable_id(champ)` |
| `app/lib/mes_demarches_to_baserow/data_extractor.rb` (modifier) | Mode exclusif quand un Mapping est fourni |
| `app/lib/mes_demarches_to_baserow/sync_coordinator.rb` (modifier) | Lecture de la révision, construction du Mapping, passage à l'extracteur, blocs ignorés |
| `app/lib/baserow_sync.rb` (modifier) | `:mapping` autorisé, erreurs de config, lambda de gabarit |
| `app/lib/mes_demarches_to_baserow/README.md`, `docs/CONFIGURATION_GUIDE.md` (modifier) | Documentation du bloc `mapping:` |

---

### Task 1: objet `Mapping` (validation et garde-fous)

**Files:**
- Create: `app/lib/mes_demarches_to_baserow/mapping.rb`
- Modify: `app/lib/referentiel/reference_pj.rb`
- Test: `spec/lib/mes_demarches_to_baserow/mapping_spec.rb`, `spec/lib/referentiel/reference_pj_spec.rb`

**Interfaces:**
- Produces:
  - `Referentiel::ReferencePj.stable_id(champ) -> Integer` (décode `champ.id` ; lève `ArgumentError` comme `pour`).
  - `MesDemarchesToBaserow::Mapping.erreurs_de_config(config) -> Array<String>` : `config` non Hash, ou valeur ni `Integer` ni `String`.
  - `MesDemarchesToBaserow::Mapping.new(config, field_metadata:, champs:, annotations:)` où `champs` / `annotations` : `Hash{Integer stable_id => String libellé}` (révisions brouillon ∪ publiée).
  - `#entrees -> Array<Entree>` avec `Entree = Struct.new(:colonne, :stable_id, :gabarit)` (un seul des deux renseigné).
  - `#avertissements -> Array<String>`.

- [ ] **Step 0: Vérifier le format des identifiants de descripteur**

Run: `bin/rails runner 'r = MesDemarches.query(MesDemarches::Queries::DemarcheRevision, variables: { demarche: 3190 }); d = (r.data.demarche.published_revision || r.data.demarche.draft_revision).champ_descriptors.first; puts d.id, Base64.urlsafe_decode64(d.id)'`
Expected : un identifiant clair de forme `<Préfixe>-<chiffres>`. Noter le préfixe réel ; la tâche 3 en extrait le `stable_id` (chiffres finaux) et les tests de la tâche 3 utilisent ce préfixe.

- [ ] **Step 1: Tests qui échouent** (`mapping_spec.rb`)

```ruby
let(:metadata) do
  { 'Service' => { 'type' => 'single_select' }, 'Représentant nom' => { 'type' => 'text' },
    'Statuts' => { 'type' => 'text', 'reference_pj' => true }, 'Début de mandat' => { 'type' => 'date' } }
end
let(:champs) { { 140_066 => 'NOM Président(e)', 140_102 => 'Statuts en vigueur', 150_001 => 'Adresse postale' } }
let(:annotations) { { 160_000 => 'Montant accordé' } }
def mapping(config) = described_class.new(config, field_metadata: metadata, champs:, annotations:)

it 'retient un stable_id et une constante sur single_select' do
  m = mapping('Représentant nom' => 140_066, 'Service' => 'DIREN')
  expect(m.entrees.map(&:to_a)).to contain_exactly(['Représentant nom', 140_066, nil], ['Service', nil, 'DIREN'])
  expect(m.avertissements).to be_empty
end
it 'ignore une colonne absente de la table' do
  expect(mapping('Inconnue' => 140_066).entrees).to be_empty
end
it 'ignore un gabarit sur une colonne date' do
  m = mapping('Début de mandat' => '{Adresse postale}')
  expect(m.entrees).to be_empty
  expect(m.avertissements.first).to include('Début de mandat')
end
it 'ignore un stable_id inconnu de la démarche' do
  expect(mapping('Représentant nom' => 999).entrees).to be_empty
end
it 'ignore un stable_id d\'annotation privée' do
  expect(mapping('Représentant nom' => 160_000).avertissements.first).to include('annotation')
end
it 'ignore un gabarit dont un libellé est inconnu (préfixe;suffixe et ternaire compris)' do
  expect(mapping('Représentant nom' => '{, ;Inconnu}').entrees).to be_empty
  expect(mapping('Représentant nom' => '{Adresse postale ? oui : non}').entrees.size).to eq(1)
end
it 'garde une chaîne numérique comme constante mais avertit' do
  m = mapping('Représentant nom' => '140066')
  expect(m.entrees.first.gabarit).to eq('140066')
  expect(m.avertissements.first).to include('stable_id')
end
describe '.erreurs_de_config' do
  it { expect(described_class.erreurs_de_config('x')).not_to be_empty }
  it { expect(described_class.erreurs_de_config('A' => 1.5)).not_to be_empty }
  it { expect(described_class.erreurs_de_config('A' => 1, 'B' => 'x')).to be_empty }
end
```

Et dans `reference_pj_spec.rb` : `ReferencePj.stable_id(double(id: Base64.urlsafe_encode64('Champ-155122|01HZX')))` vaut `155122`.

- [ ] **Step 2: Lancer** `bundle exec rspec spec/lib/mes_demarches_to_baserow/mapping_spec.rb spec/lib/referentiel/reference_pj_spec.rb` — Expected : FAIL (`uninitialized constant`).

- [ ] **Step 3: Implémenter.** Les libellés d'un gabarit s'extraient avec la même expression que `FieldChecker#instanciate_once` (`/{(?:([^{};]*);)?([^{}]+?)(?:;([^{};]*))?}/`, groupe 2) ; pour un ternaire, garder la partie avant `?`, `strip`. Un gabarit sans accolade ne référence rien (constante). Les avertissements sont des phrases françaises qui nomment la colonne et la cause.

- [ ] **Step 4: Relancer** — Expected : PASS.

- [ ] **Step 5: Commit** `feat(baserow_sync): objet Mapping (stable_id ou gabarit) et garde-fous non destructifs`

---

### Task 2: extraction en mode mapping

**Files:**
- Modify: `app/lib/mes_demarches_to_baserow/data_extractor.rb`
- Test: `spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb` (nouveau `describe 'avec mapping'`)

**Interfaces:**
- Consumes: `Mapping#entrees`, `Referentiel::ReferencePj.stable_id`.
- Produces: `DataExtractor.new(field_metadata, options, block_columns:, referentiel:, mapping: nil, gabarit: nil)` où `gabarit : ->(String) { String }`. Avec `mapping`, `extract_all` rend `{ main_table: système + colonnes mappées, repetable_blocks: {} }`.

- [ ] **Step 1: Tests qui échouent** — doubles de champs comme le bloc DLNUF existant (ligne ~607 : `id: Base64.urlsafe_encode64('Champ-<n>')`), `mapping` = `instance_double(MesDemarchesToBaserow::Mapping, entrees: [...])`.

```ruby
it 'écrit la valeur du champ désigné par son stable_id sous le nom canonique' do
  data = extractor.extract_all(dossier_avec(texte('NOM Président(e)', 'Champ-140066', 'Teriierooiterai')))
  expect(data[:main_table]['Représentant nom']).to eq('Teriierooiterai')
  expect(data[:main_table]).not_to have_key('NOM Président(e)')
end
it 'vide la colonne si le champ est absent du dossier (masqué par une condition)' do
  expect(extractor.extract_all(dossier_avec)[:main_table]).to include('Représentant nom' => nil)
end
it 'écrit la constante et le gabarit instancié ; un gabarit vide donne nil' do
  # gabarit: ->(t) { t == '{Vide}' ? '' : t.delete('{}') }
  expect(data[:main_table]).to include('Service' => 'DIREN', 'Adresse' => nil)
end
it 'garde les métadonnées système (Raison sociale, Numéro TAHITI, Date de dépôt)' do
  expect(data[:main_table].keys).to include('Raison sociale', 'Numéro TAHITI', 'Date de dépôt')
end
it 'n\'écrit pas un champ homonyme d\'une colonne non mappée, ni une annotation' do
  # champ « Statuts » présent dans le dossier, colonne « Statuts » dans field_metadata, absente du mapping
  expect(data[:main_table]).not_to have_key('Statuts')
end
it 'en DLNUF, écrit la référence d\'une pièce mappée' do
  expect(data[:main_table]['Statuts']).to eq('md:42:140102')
end
it 'ne produit aucun bloc répétable' do
  expect(data[:repetable_blocks]).to eq({})
end
```

- [ ] **Step 2: Lancer** `bundle exec rspec spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb` — Expected : FAIL sur les nouveaux exemples seulement.

- [ ] **Step 3: Implémenter.** `extract_main_table` : si `@mapping`, rendre `extract_system_fields(dossier).merge(extract_mapped(dossier))`. `extract_mapped` indexe `dossier.champs` (hors `RepetitionChamp`) par `ReferencePj.stable_id` (un champ à l'identifiant illisible est ignoré avec avertissement, comme `reference_pj`). Pour une entrée `stable_id` : champ absent → `nil` ; sinon réutiliser la conversion par type de `extract_fields` en l'extrayant dans une méthode privée `valeur_colonne(data, colonne, champ, numero_dossier)` utilisée par les deux chemins (clé d'écriture = `colonne`, pas `champ.label` ; adapter `extract_reference_pj` et la lecture des fichiers existants pour recevoir la colonne). Pour une entrée gabarit : `@gabarit.call(gabarit).presence`. `extract_repetable_blocks` rend `{}` si `@mapping`.

- [ ] **Step 4: Relancer** tout `spec/lib/mes_demarches_to_baserow` — Expected : PASS, specs existantes inchangées.

- [ ] **Step 5: Commit** `feat(baserow_sync): extraction keyée stable_id et gabarits quand un mapping est déclaré`

---

### Task 3: câblage `BaserowSync` → `SyncCoordinator`

**Files:**
- Modify: `app/lib/baserow_sync.rb`, `app/lib/mes_demarches_to_baserow/sync_coordinator.rb`
- Test: `spec/lib/baserow_sync_spec.rb` (existant ou à créer), `spec/lib/mes_demarches_to_baserow/sync_coordinator_spec.rb`

**Interfaces:**
- Consumes: `Mapping.erreurs_de_config`, `Mapping.new`, `DataExtractor.new(..., mapping:, gabarit:)`.
- Produces: `SyncCoordinator.new(demarche_number, baserow_config, options = {}, mapping: nil, gabarit: nil)`.

- [ ] **Step 1: Tests qui échouent**

```ruby
# baserow_sync_spec
it 'refuse un mapping dont une valeur n\'est ni entier ni chaîne' do
  task = BaserowSync.new(baserow: { 'table_id' => 1 }, mapping: { 'A' => [1] })
  expect(task.errors.join).to include('mapping')
end
# sync_coordinator_spec (doubles du describe « type de table » existant)
it 'construit le Mapping une fois et journalise ses avertissements une fois par passe' do
  expect(Rails.logger).to receive(:warn).with(/BaserowSync mapping:.*Inconnue/).once
  coordinator = described_class.new(main_table_id, baserow_config, {}, mapping: { 'Inconnue' => 1 }, gabarit: ->(t) { t })
  2.times { coordinator.sync_dossier(dossier) }
end
it 'sans mapping, ne lit pas la révision de la démarche' do
  expect(MesDemarches).not_to receive(:query).with(MesDemarches::Queries::DemarcheRevision, anything)
  described_class.new(main_table_id, baserow_config, {})
end
```

- [ ] **Step 2: Lancer** les deux specs — Expected : FAIL.

- [ ] **Step 3: Implémenter.**
  - `BaserowSync#authorized_fields` : `+ %i[options mapping]` ; dans `initialize`, `@errors.concat(Mapping.erreurs_de_config(@params[:mapping]).map { "baserow_sync : #{_1}" })` si `@params[:mapping]` présent ; `coordinator_for` passe `mapping: @params[:mapping], gabarit: ->(t) { instanciate(t) }` (`@dossier` est posé par `FieldChecker#process` avant l'appel).
  - `SyncCoordinator#initialize` : si `mapping`, lire `DemarcheRevision` une fois, construire `champs` / `annotations` (`{ stable_id => libellé }`, brouillon ∪ publiée, stable_id = chiffres finaux de l'identifiant décodé, préfixe constaté au step 0 de la tâche 1), construire le `Mapping`, journaliser chaque avertissement préfixé `BaserowSync mapping: démarche <n>, `. `sync_dossier` passe `mapping:` / `gabarit:` à `DataExtractor` ; `sync_repetable_blocks` n'est pas appelé quand un mapping est déclaré.

- [ ] **Step 4: Relancer** `bundle exec rspec spec/lib/baserow_sync_spec.rb spec/lib/mes_demarches_to_baserow` — Expected : PASS.

- [ ] **Step 5: Commit** `feat(baserow_sync): bloc mapping dans la configuration, révision lue une fois par passe`

---

### Task 4: documentation

**Files:**
- Modify: `app/lib/mes_demarches_to_baserow/README.md` (nouvelle section « Mapping vers une table socle » après « Référentiel DLNUF »), `docs/CONFIGURATION_GUIDE.md` (entrée `baserow_sync` → option `mapping`)

- [ ] **Step 1: Rédiger** : l'exemple YAML du §2.2 du devis ; les deux formes ; types admis pour un gabarit ; les six garde-fous ; le mode exclusif (plus d'appariement par libellé, pas de blocs, pas d'annotations, métadonnées système gardées) ; la règle « constante seulement si le formulaire impose la valeur » ; « un gabarit peut lire une annotation privée, ce qui sort de la règle champ-only » ; « une colonne composée ne se redécoupe pas au préremplissage ».
- [ ] **Step 2: Commit** `docs(baserow_sync): mapping vers une table socle`

---

### Task 5: conformer la table socle 1046 et recette sur un dossier réel

La table 1046 (base 284, espace Financeurs) a été créée le 16/11 hors builder : 9 colonnes `file` (refusées en DLNUF), aucun marqueur, « N° Tahiti » au lieu du nom système « Numéro TAHITI ». Elle est vide.

- [ ] **Step 1: Script** (`rails runner`, scratchpad, jamais commité) avec `Baserow::StructureClient` :
  - pour chaque colonne `file` (`Statuts`, `Extrait JOPF`, `PV d'AG statuts`, `Liste ou PV des dirigeants`, `RIB`, `Bilan financier N-1`, `Budget prévisionnel`, `PV d'AG comptes et budget`, `Attestation de non-changement`) : `update_field(id, type: 'text', description: 'mes-demarches: reference=piece_justificative')` ;
  - renommer `N° Tahiti` en `Numéro TAHITI` ;
  - poser sur `Dossier` la description `Referentiel::Marqueur.description_table(mode: :dlnuf, proprietaire: <id de « Propriétaire »>)`.
- [ ] **Step 2: Vérifier** : `Referentiel::Marqueur.type_table(description de Dossier)` vaut `[:dlnuf, <id>]` et plus aucune colonne `file`.
- [ ] **Step 3: Recette** sur un dossier DIREN 3190 réel, en local : config temporaire `baserow_sync` (table 1046, `token_config` de l'espace Financeurs, `mapping:` avec 3 stable_id, `Service: DIREN`, `Représentant fonction: Président`) ; `SyncCoordinator#sync_dossier` sur ce seul dossier. Attendu : une ligne avec les colonnes mappées, les références `md:`, `Propriétaire` en minuscules, `Libellé` = « DIREN – dossier du … » ; journal sans avertissement. Puis `delete_dossier(numero)` pour laisser la table vide.
- [ ] **Step 4:** Noter le résultat dans le compte rendu de la branche ; pas de commit (aucun fichier versionné touché).
