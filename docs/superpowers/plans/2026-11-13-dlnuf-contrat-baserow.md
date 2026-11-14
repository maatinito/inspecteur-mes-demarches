# Référentiel DLNUF côté robot (builder et synchro Baserow, effacement) — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Objectif :** appliquer dans le robot le contrat « référentiel DLNUF » pour Baserow : le builder crée une table DLNUF marquée, la synchro la reconnaît, y écrit l'e-mail du titulaire et des références de pièces au lieu de fichiers, et efface les lignes des dossiers supprimés.

**Architecture :** le type d'une table (archive ou DLNUF) est déclaré une seule fois, par le builder, dans la description de la colonne primaire Baserow. Le builder ne se fie qu'à ce marqueur, jamais à sa propre base : il peut donc tourner sur un autre environnement que le robot qui synchronise. Le robot qui synchronise enregistre le type à sa **première lecture** dans une table `referentiel_tables` ; ce type est alors **figé** pour lui : à chaque passage il compare le marqueur lu au type enregistré et refuse tout (ni écriture ni effacement) s'ils diffèrent. L'effacement passe par un nouveau hook générique `InspectorTask#deleted`, alimenté par les flux GraphQL `pendingDeletedDossiers` et `deletedDossiers` sur le curseur `checked_at` existant.

**Pile technique :** Rails, RSpec, Baserow 2.0.6 (API REST, JWT pour la structure, jeton de base pour les lignes), GraphQL Mes-Démarches (schéma chargé par introspection au démarrage).

**Specs :**
- Contrat : `../mes-demarches/docs/superpowers/specs/2026-11-06-contrat-referentiel-dlnuf.md`
- Lot C (lecteur des références) : `../mes-demarches/docs/superpowers/specs/2026-11-06-prefill-piece-justificative-reference-md-design.md`
- Devis : `docs/superpowers/specs/2026-07-22-devis-dlnuf-subventions-global.md` (lots W1 partiel et W2)
- Décisions du 13/11/2026 ci-dessous : elles **priment** sur le contrat là où elles le contredisent.

## Décisions du 13/11/2026 (amendent le contrat)

1. **Type figé.** Le type d'une table ne change jamais. Les transitions du contrat §3.4 (`DLNUF → archive`, `archive → DLNUF` avec confirmation) et la procédure de retour à archive sont supprimées. Pour changer de type, on crée une autre table.
2. **Refus, pas de réécriture automatique.** Marqueur lu ≠ type enregistré ⇒ la synchro n'écrit rien, n'efface rien, alerte. Le marqueur n'est réécrit que par un geste humain dans le builder (« Rétablir le marqueur »), et seulement avec le type enregistré.
2 bis. **Builder et synchro sur des robots différents.** Le builder est souvent utilisé depuis dev ou staging, la synchro tourne en production. Donc : le builder décide d'après le marqueur lu sur la table (il ne pose un marqueur DLNUF que sur une table qu'il vient de créer, et ne modifie jamais un marqueur existant) ; le robot qui synchronise adopte le type lu à sa première lecture, même si la table contient déjà des lignes (démarche recettée en staging puis basculée en production), et envoie dans ce cas un courriel d'information sans rien bloquer. « Rétablir le marqueur » se fait sur le robot qui a alerté, seul à connaître le type figé.
3. **Table Avis ignorée en DLNUF** : ni créée par le builder, ni synchronisée.
4. **Blocs répétables** : leurs lignes sont effacées avec la ligne du dossier. Les pièces d'un bloc sont des références `md:<numero>:<stable_id>:<row_id>`.
5. **Effacement par deux flux**, même curseur `checked_at`, sans marge : `pendingDeletedDossiers` (suppression par l'administration, ou par l'usager en construction, dès le clic) et `deletedDossiers` (expiration, suppression de compte). Un dossier restauré repasse par `dossiers(updatedSince:)` et sa ligne est recréée.
5 bis. **Dossier supprimé par l'usager seul** (dossier terminé, encore visible de l'administration) : il n'apparaît dans aucun des deux flux, mais la suppression modifie le dossier, qui revient par `dossiers(updatedSince:)` avec `dateSuppressionParUsager` renseigné. En DLNUF, la synchro efface alors sa ligne au lieu de l'écrire. Si l'usager le restaure, l'attribut se vide et la ligne est recréée.
6. **« Vider la table »** (DLNUF seulement) : efface toutes les lignes puis remet le curseur de la démarche à `EPOCH`. Sert à la publication (les dossiers de test ne sont pas tracés par MD) et à la reprise.
7. **Ordre** : ce plan couvre le contrat sur table dédiée (appariement par libellé). La table socle commune et le `mapping:` par `stable_id` (P0, reste de W1) viennent dans un plan ultérieur.
8. **Grist hors périmètre.** Le contrat renvoie le marqueur Grist à plus tard et aucun lecteur n'existe côté MD. Une table Grist reste donc en archive, où rien ne s'efface : `GristSync#deleted` n'a rien à faire aujourd'hui. Le hook `deleted` étant générique, la parité se fera en le surchargeant quand le marqueur Grist existera.

Hors de ce dépôt, transmis à la session mes-demarches : réécriture du contrat §3.4 selon les décisions 1 à 4, et filtre `visible_by_user` sur les lignes proposées en DLNUF (contrat §5.3), devenu facultatif depuis la décision 5 bis. Le détail est en annexe.

## Contraintes globales

- Avant chaque commit : `bundle exec rubocop -A` puis `bundle exec rake lint` (CLAUDE.md).
- Travailler sur une branche `dlnuf-contrat` partie de `dev` ; jamais de push direct sur `master`.
- Mode archive : **comportement actuel inchangé** (copie des fichiers, aucun effacement). Toute spec existante de `spec/lib/mes_demarches_to_baserow` et `spec/lib/schema_builders` reste verte sans modification de ses attentes.
- Règles d'analyse du marqueur **identiques** à `../mes-demarches/app/lib/referentiel_de_polynesie/marqueur.rb` (contrat §3.2).
- Texte exact du marqueur de table (deux lignes, contrat §3.2) :
  `Référentiel DLNUF : lignes effacées avec leur dossier Mes-Démarches. Ne pas modifier la ligne suivante.`
  `mes-demarches: referentiel=DLNUF; proprietaire=<id>`
- Texte exact du marqueur de colonne (contrat §4.1) : `mes-demarches: reference=piece_justificative`
- Format d'une référence (contrat §4.2) : `md:<numero_dossier>:<stable_id>` ou `md:<numero_dossier>:<stable_id>:<row_id>`. Une référence par cellule ; cellule vide = pas de pièce.
- Effacement **idempotent** : ligne absente = succès silencieux.
- Sous-hash YAML : clés chaînes (`@params[:baserow]['table_id']`).
- Ne pas incrémenter `BaserowSync#version` (un retraitement général n'est pas voulu).

## Points de vigilance pour la revue

1. **Marqueur modifié pendant que des dossiers sont supprimés** : la synchro refuse, le curseur avance, les suppressions de la période sont perdues. Attendu : l'alerte donne la date du premier refus (`refus_depuis`) pour reculer `checked_at` après rétablissement. Test en tâche 2.
2. **Table DLNUF contenant une colonne `file`** (ajoutée à la main) : attendu, refus de toute la table à l'initialisation, pas un échec dossier par dossier. Test en tâche 6.
3. **Refus sur une démarche de 500 dossiers** : attendu, un seul courriel par table et par 24 h, pas un par dossier ; les dossiers restent en échec et sont rejoués après rétablissement. Tests en tâches 2 et 6.
4. **Pièce retirée par l'usager** : la cellule de référence doit être vidée (`nil`), pas laissée. Test en tâche 7.
5. **Dossier jamais synchronisé puis supprimé**, ou suppression rejouée après remise du curseur : aucune erreur, aucune ligne touchée. Test en tâche 9.

---

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `app/lib/referentiel/marqueur.rb` (créer) | Analyse et rédaction des marqueurs `mes-demarches:` |
| `app/models/referentiel_table.rb` + migration (créer) | Type figé d'une table cible pour le robot qui la synchronise, état de refus |
| `app/lib/referentiel/verrou.rb` (créer) | Compare marqueur lu et type enregistré ; lève `Refus` |
| `app/lib/referentiel/alerte.rb` (créer) | Courriel et Sentry, au plus une fois par 24 h et par table |
| `app/lib/referentiel/reference_pj.rb` (créer) | Fabrique `md:<n>:<stable_id>[:<row_id>]` depuis un champ GraphQL |
| `app/lib/schema_builders/type_mapper.rb` (modifier) | Variante DLNUF : PJ en texte marqué |
| `app/lib/schema_builders/referentiel_dlnuf.rb` (créer) | Lecture, pose et rétablissement du marqueur de table Baserow |
| `app/lib/schema_builders/baserow_target.rb`, `app/lib/baserow/structure_client.rb` (modifier) | Lecture et effacement de lignes par lot |
| `app/models/schema_target.rb` + migration (modifier) | Choix `referentiel` de la cible |
| `app/controllers/admin/schema_builder_controller.rb`, vues `app/views/admin/schema_builder/` (modifier) | Choix du type, refus, « Rétablir le marqueur », « Vider la table » |
| `app/lib/mes_demarches_to_baserow/sync_coordinator.rb`, `data_extractor.rb` (modifier) | Mode lu au démarrage, comportements DLNUF, `delete_dossier` |
| `app/lib/baserow_sync.rb` (modifier) | `#deleted` |
| `app/lib/inspector_task.rb`, `dossier_actions.rb`, `mes_demarches.rb`, `verification_service.rb` (modifier) | Hook `deleted` et boucle des suppressions |

---

### Task 1: analyse et rédaction du marqueur

**Fichiers :**
- Créer : `app/lib/referentiel/marqueur.rb`
- Test : `spec/lib/referentiel/marqueur_spec.rb`

**Interfaces :**
- Produit :
  - `Referentiel::Marqueur.parse(texte) -> nil | :invalid | Hash{String=>String}` (clés en minuscules)
  - `Referentiel::Marqueur.type_table(texte) -> [:archive, nil] | [:dlnuf, Integer] | :invalid`
  - `Referentiel::Marqueur.reference_pj?(texte) -> Boolean`
  - `Referentiel::Marqueur.description_table(mode:, proprietaire: nil, existante: nil) -> String`
  - `Referentiel::Marqueur::LIGNE_REFERENCE_PJ = 'mes-demarches: reference=piece_justificative'`

- [ ] **Étape 1 : écrire les tests qui échouent**

```ruby
describe Referentiel::Marqueur do
  describe '.parse' do
    it { expect(described_class.parse(nil)).to be_nil }
    it { expect(described_class.parse("Numéro du dossier")).to be_nil }
    it { expect(described_class.parse("x\n  MES-DEMARCHES:  Referentiel = DLNUF ;proprietaire=12 ; inconnue=1")).to eq('referentiel' => 'DLNUF', 'proprietaire' => '12', 'inconnue' => '1') }
    it('deux lignes') { expect(described_class.parse("mes-demarches: a=1\nmes-demarches: b=2")).to eq(:invalid) }
    it('faute de préfixe') { expect(described_class.parse('mes démarches : referentiel=DLNUF')).to eq(:invalid) }
    it('clé répétée') { expect(described_class.parse('mes-demarches: a=1; a=2')).to eq(:invalid) }
    it('sans paire') { expect(described_class.parse('mes-demarches:')).to eq(:invalid) }
    it('sans =') { expect(described_class.parse('mes-demarches: DLNUF')).to eq(:invalid) }
    it('contrat inconnu') { expect(described_class.parse('mes-demarches: referentiel=DLNUF; contrat=2')).to eq(:invalid) }
  end

  describe '.type_table' do
    it { expect(described_class.type_table(nil)).to eq([:archive, nil]) }
    it { expect(described_class.type_table('mes-demarches: referentiel=archive')).to eq([:archive, nil]) }
    it { expect(described_class.type_table('mes-demarches: contrat=1')).to eq([:archive, nil]) }
    it { expect(described_class.type_table('mes-demarches: referentiel=dlnuf; proprietaire=9115')).to eq([:dlnuf, 9115]) }
    it('DLNUF sans propriétaire') { expect(described_class.type_table('mes-demarches: referentiel=DLNUF')).to eq(:invalid) }
    it('propriétaire non numérique') { expect(described_class.type_table('mes-demarches: referentiel=DLNUF; proprietaire=Email')).to eq(:invalid) }
    it('type inconnu') { expect(described_class.type_table('mes-demarches: referentiel=autre')).to eq(:invalid) }
    it('clé présente mais vide') { expect(described_class.type_table('mes-demarches: referentiel=')).to eq(:invalid) }
  end

  describe '.reference_pj?' do
    it { expect(described_class.reference_pj?("Statuts\nmes-demarches: reference=Piece_Justificative")).to be true }
    it { expect(described_class.reference_pj?('Statuts')).to be false }
    it { expect(described_class.reference_pj?('mes-demarches: reference=autre')).to be false }
    it('illisible') { expect(described_class.reference_pj?("mes-demarches: a\nmes-demarches: b")).to be false }
  end

  describe '.description_table' do
    it 'rédige les deux lignes du contrat' do
      expect(described_class.description_table(mode: :dlnuf, proprietaire: 12_345)).to eq(
        "Référentiel DLNUF : lignes effacées avec leur dossier Mes-Démarches. Ne pas modifier la ligne suivante.\n" \
        'mes-demarches: referentiel=DLNUF; proprietaire=12345'
      )
    end

    it 'remplace un marqueur existant et garde le reste' do
      existante = "Numéro du dossier\nRéférentiel DLNUF : lignes effacées avec leur dossier Mes-Démarches. Ne pas modifier la ligne suivante.\nmes demarches: referentiel=archive"
      resultat = described_class.description_table(mode: :dlnuf, proprietaire: 7, existante:)
      expect(resultat.lines.map(&:chomp)).to eq(['Numéro du dossier',
                                                 'Référentiel DLNUF : lignes effacées avec leur dossier Mes-Démarches. Ne pas modifier la ligne suivante.',
                                                 'mes-demarches: referentiel=DLNUF; proprietaire=7'])
      expect(described_class.type_table(resultat)).to eq([:dlnuf, 7])
    end

    it 'retire le marqueur en archive' do
      expect(described_class.description_table(mode: :archive, existante: "Numéro du dossier\nmes-demarches: referentiel=DLNUF; proprietaire=7")).to eq('Numéro du dossier')
    end
  end
end
```

- [ ] **Étape 2 :** `bundle exec rspec spec/lib/referentiel/marqueur_spec.rb` — attendu : échec, `uninitialized constant Referentiel`.

- [ ] **Étape 3 : implémenter.** `parse` est un portage à l'identique de `ReferentielDePolynesie::Marqueur.parse` du dépôt voisin (mêmes constantes `CONTRATS_CONNUS`, `CANDIDAT`, `PREFIXE`). `description_table` retire de `existante` les lignes qui correspondent à `CANDIDAT` ainsi que la ligne lisible du contrat, puis ajoute les deux lignes en DLNUF. Un commentaire en tête de fichier renvoie au fichier source de Mes-Démarches : toute évolution des règles se fait dans les deux dépôts.

- [ ] **Étape 4 :** relancer la spec — attendu : tout passe.

- [ ] **Étape 5 :** `bundle exec rubocop -A && bundle exec rake lint`, puis commit `feat(referentiel): analyse et rédaction du marqueur mes-demarches (contrat DLNUF §3.2)`.

---

### Task 2: type figé, verrou et alerte

**Fichiers :**
- Créer : `db/migrate/<horodatage>_create_referentiel_tables.rb`, `app/models/referentiel_table.rb`, `app/lib/referentiel/verrou.rb`, `app/lib/referentiel/alerte.rb`
- Test : `spec/models/referentiel_table_spec.rb`, `spec/lib/referentiel/verrou_spec.rb`, `spec/lib/referentiel/alerte_spec.rb`

**Interfaces :**
- Consomme : `Referentiel::Marqueur.type_table` (tâche 1).
- Produit :
  - Table `referentiel_tables` : `backend` (string, non nul), `table_ref` (string, non nul), `mode` (string, non nul : `'archive'` ou `'dlnuf'`), `proprietaire` (bigint, nul), `refus_depuis` (datetime, nul), `alerte_le` (datetime, nul), horodatages ; index unique `(backend, table_ref)`.
  - `ReferentielTable#dlnuf? -> Boolean`
  - `Referentiel::Verrou.mode!(backend:, table_ref:, description_primaire:, lignes:) -> :archive | :dlnuf` ; `lignes` est un lambda sans argument rendant le nombre de lignes de la table, appelé seulement à la première lecture d'une table DLNUF. Lève `Referentiel::Verrou::Refus`.
  - `Referentiel::Verrou::Refus < StandardError`, avec `#table -> ReferentielTable`.
  - `Referentiel::Alerte.signaler(refus) -> Boolean` (vrai si un courriel est parti).
  - `Referentiel::Alerte.informer(table, message)` : courriel d'information, sans limite de fréquence (appelé une seule fois par table).

Règles de `mode!` (le type lu vient de `Marqueur.type_table(description_primaire)`) :

| Enregistrement | Marqueur lu | Résultat |
|---|---|---|
| quelconque | `:invalid` | `Refus` (« marqueur illisible ») ; sans enregistrement, en créer un en `archive` d'abord |
| absent | archive | créer `archive`, rendre `:archive` |
| absent | DLNUF | créer `dlnuf` avec son propriétaire, rendre `:dlnuf` ; si `lignes.call` est positif, `Alerte.informer` (« table <ref> adoptée en DLNUF, <n> lignes déjà présentes ») |
| `archive` | archive | `:archive` |
| `dlnuf` | DLNUF, même propriétaire | `:dlnuf` |
| tout autre cas | | `Refus` (« type ou propriétaire modifié ») |

Sur un refus : poser `refus_depuis` à l'heure courante s'il est nul, **avant** de lever (via `update_columns`, pour survivre à l'exception). Sur un succès : remettre `refus_depuis` et `alerte_le` à nul s'ils ne le sont pas. Le message du `Refus` nomme le backend, la table, le type enregistré, le type lu et `refus_depuis`.

`Alerte.signaler` : ne fait rien si `alerte_le` date de moins de 24 h ; sinon envoie `NotificationMailer.with(message:, tags:).report_error.deliver_later` (même forme que dans `VerificationService#apply_control`), appelle `Sentry.capture_message`, et pose `alerte_le`. Le message ajoute au texte du refus : « Synchronisation et effacement suspendus. Rétablir le marqueur dans le builder, puis reculer le curseur de la démarche au <refus_depuis> pour rejouer les suppressions manquées. »

- [ ] **Étape 1 : tests du verrou** (un `it` par ligne du tableau ci-dessus, plus ceux-ci) :

```ruby
it 'ne compte pas les lignes quand le marqueur est archive' do
  lignes = -> { raise 'ne doit pas être appelé' }
  expect(described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: nil, lignes:)).to eq(:archive)
end

it 'adopte sans courriel une table DLNUF vide' do
  expect(Referentiel::Alerte).not_to receive(:informer)
  expect(described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: 'mes-demarches: referentiel=DLNUF; proprietaire=7', lignes: -> { 0 })).to eq(:dlnuf)
end

it 'adopte une table DLNUF déjà remplie et en informe une seule fois' do
  expect(Referentiel::Alerte).to receive(:informer).once.with(an_instance_of(ReferentielTable), /adoptée en DLNUF, 128 lignes/)
  2.times { described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: 'mes-demarches: referentiel=DLNUF; proprietaire=7', lignes: -> { 128 }) }
  expect(ReferentielTable.find_by(table_ref: '42')).to have_attributes(mode: 'dlnuf', proprietaire: 7)
end

it 'date le premier refus et le garde aux refus suivants' do
  ReferentielTable.create!(backend: 'baserow', table_ref: '42', mode: 'dlnuf', proprietaire: 7)
  2.times { expect { described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: nil, lignes: -> { 0 }) }.to raise_error(Referentiel::Verrou::Refus) }
  expect(ReferentielTable.last.refus_depuis).to be_within(5.seconds).of(Time.zone.now)
end

it 'efface la date de refus quand le marqueur est rétabli' do
  table = ReferentielTable.create!(backend: 'baserow', table_ref: '42', mode: 'dlnuf', proprietaire: 7, refus_depuis: 1.day.ago, alerte_le: 1.day.ago)
  described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: 'mes-demarches: referentiel=DLNUF; proprietaire=7', lignes: -> { 3 })
  expect(table.reload).to have_attributes(refus_depuis: nil, alerte_le: nil)
end
```

- [ ] **Étape 2 : tests de l'alerte** : un courriel au premier appel (`have_enqueued_mail(NotificationMailer, :report_error)`), aucun au second dans les 24 h, un nouveau après `travel 25.hours`.

- [ ] **Étape 3 :** lancer les trois specs — attendu : échec (constantes absentes).

- [ ] **Étape 4 :** écrire la migration, `bin/rails db:migrate`, le modèle (validations de présence, `mode` dans `%w[archive dlnuf]`, unicité `table_ref` par `backend`), `Verrou` et `Alerte`.

- [ ] **Étape 5 :** relancer — attendu : tout passe.

- [ ] **Étape 6 :** rubocop, lint, commit `feat(referentiel): type de table figé, verrou et alerte`.

---

### Task 3: colonnes DLNUF dans le builder (PJ en texte marqué, e-mail obligatoire)

**Fichiers :**
- Modifier : `app/lib/schema_builders/type_mapper.rb` (`self.for`, `initialize`, `map_field_type`), `app/models/schema_target.rb`, `app/controllers/admin/schema_builder_controller.rb` (`main_table_builder_for`, `block_builder_for`, `differ_for`, `build_main_table`, `toggle_main_table_field_exclusion`), `app/views/admin/schema_builder/_field_checkbox.html.haml`
- Créer : `db/migrate/<horodatage>_add_referentiel_to_schema_targets.rb`
- Test : `spec/lib/schema_builders/type_mapper_spec.rb`, `spec/models/schema_target_spec.rb`, `spec/lib/schema_builders/main_table_builder_spec.rb`, `spec/lib/schema_builders/block_builder_spec.rb`

**Interfaces :**
- Consomme : `Referentiel::Marqueur::LIGNE_REFERENCE_PJ`.
- Produit :
  - `SchemaBuilders::TypeMapper.for(target, referentiel: :archive)` ; `referentiel: :dlnuf` n'est accepté que pour `:baserow` (`ArgumentError` sinon).
  - Colonne `schema_targets.referentiel` (string, non nul, défaut `'archive'`).
  - `SchemaTarget#dlnuf? -> Boolean`
  - `SchemaTarget#exclusions_effectives -> Array<String>` : `excluded_field_ids` sans `'metadata:email_usager'` en DLNUF.
  - `SchemaTarget#type_mapper -> SchemaBuilders::TypeMapper` (mode de la cible).

- [ ] **Étape 1 : tests**

```ruby
# type_mapper_spec.rb
it 'mappe une PJ en texte marqué pour une table DLNUF' do
  mapper = SchemaBuilders::TypeMapper.for(:baserow, referentiel: :dlnuf)
  expect(mapper.field_spec('Statuts', 'PieceJustificativeChampDescriptor', {}))
    .to eq(type: 'text', name: 'Statuts', description: 'mes-demarches: reference=piece_justificative')
end

it 'garde la PJ en fichier pour une table archive' do
  expect(SchemaBuilders::TypeMapper.for(:baserow).field_spec('Statuts', 'PieceJustificativeChampDescriptor', {})).to eq(type: 'file', name: 'Statuts')
end

it('refuse DLNUF pour Grist') { expect { SchemaBuilders::TypeMapper.for(:grist, referentiel: :dlnuf) }.to raise_error(ArgumentError) }

# schema_target_spec.rb
it 'ne laisse pas exclure Email usager en DLNUF' do
  cible = build(:schema_target, referentiel: 'dlnuf', excluded_field_ids: %w[metadata:email_usager metadata:labels])
  expect(cible.exclusions_effectives).to eq(%w[metadata:labels])
end

it 'interdit de changer de type après la première synchronisation du schéma' do
  cible = create(:schema_target, referentiel: 'archive', last_synced_at: Time.zone.now)
  expect(cible.update(referentiel: 'dlnuf')).to be false
end

it('refuse DLNUF sur une cible Grist') { expect(build(:schema_target, target_type: 'grist', referentiel: 'dlnuf')).not_to be_valid }
```

Ajouter dans `main_table_builder_spec.rb` et `block_builder_spec.rb` un cas qui construit avec le mapper DLNUF et vérifie que la colonne d'une PJ sort en `text` avec la description marquée (table principale et table de bloc).

- [ ] **Étape 2 :** lancer ces specs — attendu : échec.

- [ ] **Étape 3 : implémenter.** S'il n'existe pas de fabrique `:schema_target`, créer les objets comme le fait déjà `spec/models/schema_target_spec.rb`. Dans le contrôleur, remplacer les trois `SchemaBuilders::TypeMapper.for(target.target_type.to_sym)` des méthodes citées par `target.type_mapper`, passer `target.exclusions_effectives` à `build!`, et faire rendre `head :unprocessable_entity` à `toggle_main_table_field_exclusion` pour `metadata:email_usager` en DLNUF. Dans `_field_checkbox`, case désactivée et cochée pour cette colonne en DLNUF, avec la mention « obligatoire en DLNUF ».

- [ ] **Étape 4 :** `bundle exec rspec spec/lib/schema_builders spec/models/schema_target_spec.rb` — attendu : tout passe, anciennes specs comprises.

- [ ] **Étape 5 :** rubocop, lint, commit `feat(schema_builder): colonnes d'une table DLNUF (PJ en référence, e-mail obligatoire)`.

---

### Task 4: choix du type et pose du marqueur dans le builder

**Fichiers :**
- Créer : `app/lib/schema_builders/referentiel_dlnuf.rb`
- Modifier : `app/controllers/admin/schema_builder_controller.rb` (`target_selection_params`, `build_main_table`, `build_blocks`, `preview_avis`, `build_avis`, nouvelle action `retablir_marqueur`), `config/routes.rb`, `app/views/admin/schema_builder/_target_panel.html.haml`, `_main_table_section.html.haml`, `_build_result.html.haml`
- Test : `spec/lib/schema_builders/referentiel_dlnuf_spec.rb`, `spec/requests/admin/schema_builder_spec.rb` (ou la spec de requêtes existante du builder ; `bun run build` est requis en local pour les specs de requêtes)

**Interfaces :**
- Consomme : `Referentiel::Marqueur`, `Referentiel::Verrou::Refus`, `ReferentielTable` (pour `retablir!` seulement), `Baserow::StructureClient#get_table_fields`, `#update_field`.
- Produit :
  - `SchemaBuilders::ReferentielDlnuf.new(client:)` avec :
    - `#type_lu(table_id) -> :archive | :dlnuf | :invalid` : type déclaré par le marqueur de la table
    - `#colonnes_fichier(table_id) -> Array<String>` (noms des colonnes de type `file`)
    - `#finaliser!(table_id, creee:) -> Integer` : pose le marqueur sur une table neuve ou vérifie celui d'une table existante ; rend l'identifiant de la colonne propriétaire ; lève `Referentiel::Verrou::Refus`
    - `#retablir!(table_id) -> ReferentielTable` : réécrit le marqueur d'après l'enregistrement de **ce** robot

Le builder n'écrit jamais dans `referentiel_tables` : cette table appartient au robot qui synchronise (décision 2 bis).
  - Route `POST targets/:target/main_table/retablir_marqueur`, helper `retablir_marqueur_admin_demarche_schema_path`.

Règles du contrôleur :

- `referentiel` est accepté par `update_target_selection` (ajout à `target_selection_params`). Le sélecteur « Type de référentiel » (archive par défaut, DLNUF) n'apparaît que pour une cible Baserow et est désactivé dès que `last_synced_at` est renseigné.
- `build_main_table` et `build_blocks`, avant toute écriture, quand la table principale existe déjà : `type_lu` doit égaler `target.referentiel`. Sinon rien n'est modifié et le résultat porte l'erreur « Le type d'une table ne change pas : créer une nouvelle table. » (ou « Marqueur illisible sur la table » pour `:invalid`).
- En DLNUF, avant toute écriture sur une table existante : si `colonnes_fichier` n'est pas vide, rien n'est modifié et le résultat porte l'erreur « Colonne(s) fichier interdite(s) dans une table DLNUF : <noms>. »
- En DLNUF, après un `build!` réussi de la table principale : `finaliser!(table_id, creee: result[:action] == :created)`.
- `preview_avis` et `build_avis` : `head :precondition_failed` en DLNUF ; la section Avis n'est pas rendue dans `_target_panel`.
- `retablir_marqueur` : appelle `retablir!`. Le bouton n'apparaît dans la section « Table principale » que si un `ReferentielTable` existe pour la table sur ce robot, c'est-à-dire sur le robot qui la synchronise.

Règles de `finaliser!` :

1. Lire les colonnes ; la colonne primaire est celle dont `primary` est vrai ; la colonne propriétaire est celle nommée « Email usager » (nom tiré de `SchemaBuilders::MetadataFields`). Absente ⇒ `Refus`.
2. Si `Marqueur.type_table(primaire['description'])` vaut déjà `[:dlnuf, <id de la colonne propriétaire>]` : ne rien écrire.
3. Sinon, si `creee` est vrai et que le marqueur lu est `[:archive, nil]` : `update_field(primaire['id'], description: Marqueur.description_table(mode: :dlnuf, proprietaire: <id>, existante: primaire['description']))`.
4. Dans tous les autres cas (table existante sans marqueur DLNUF, propriétaire différent, marqueur illisible) : `Refus`, rien n'est réécrit.

`retablir!` : exige un enregistrement ; réécrit la description de la colonne primaire avec `Marqueur.description_table(mode:, proprietaire:, existante:)` du type **enregistré** (en archive, cela retire la ligne machine).

- [ ] **Étape 1 : tests de `ReferentielDlnuf`** avec un double de `Baserow::StructureClient` :

```ruby
let(:colonnes) do
  [{ 'id' => 1, 'name' => 'Dossier', 'type' => 'number', 'primary' => true, 'description' => nil },
   { 'id' => 9115, 'name' => 'Email usager', 'type' => 'email', 'primary' => false }]
end

it 'pose le marqueur sur une table neuve, sans rien enregistrer en base' do
  expect(client).to receive(:update_field).with(1, description: a_string_ending_with('mes-demarches: referentiel=DLNUF; proprietaire=9115'))
  expect(described_class.new(client:).finaliser!(861, creee: true)).to eq(9115)
  expect(ReferentielTable.count).to eq(0)
end

it 'ne réécrit rien quand le marqueur concorde' do
  colonnes.first['description'] = 'mes-demarches: referentiel=DLNUF; proprietaire=9115'
  expect(client).not_to receive(:update_field)
  described_class.new(client:).finaliser!(861, creee: false)
end

it 'refuse de marquer une table existante' do
  expect(client).not_to receive(:update_field)
  expect { described_class.new(client:).finaliser!(861, creee: false) }.to raise_error(Referentiel::Verrou::Refus)
end

it 'refuse un propriétaire discordant sans le réécrire' do
  colonnes.first['description'] = 'mes-demarches: referentiel=DLNUF; proprietaire=1'
  expect(client).not_to receive(:update_field)
  expect { described_class.new(client:).finaliser!(861, creee: true) }.to raise_error(Referentiel::Verrou::Refus)
end

it('refuse sans colonne Email usager') { colonnes.pop; expect { described_class.new(client:).finaliser!(861, creee: true) }.to raise_error(Referentiel::Verrou::Refus) }

it 'lit le type déclaré par la table' do
  expect(described_class.new(client:).type_lu(861)).to eq(:archive)
  colonnes.first['description'] = 'mes-demarches: referentiel=DLNUF; proprietaire=9115'
  expect(described_class.new(client:).type_lu(861)).to eq(:dlnuf)
  colonnes.first['description'] = 'mes demarches: referentiel=DLNUF'
  expect(described_class.new(client:).type_lu(861)).to eq(:invalid)
end

it('rétablir exige un enregistrement sur ce robot') { expect { described_class.new(client:).retablir!(861) }.to raise_error(Referentiel::Verrou::Refus) }

it 'rétablit le marqueur du type enregistré' do
  ReferentielTable.create!(backend: 'baserow', table_ref: '861', mode: 'archive')
  colonnes.first['description'] = "Numéro\nmes-demarches: referentiel=DLNUF; proprietaire=9115"
  expect(client).to receive(:update_field).with(1, description: 'Numéro')
  described_class.new(client:).retablir!(861)
end

it('liste les colonnes fichier') { colonnes << { 'id' => 3, 'name' => 'RIB', 'type' => 'file' }; expect(described_class.new(client:).colonnes_fichier(861)).to eq(['RIB']) }
```

- [ ] **Étape 2 : tests de requêtes** : construction DLNUF d'une table neuve appelle `finaliser!` avec `creee: true` ; cible DLNUF pointée sur une table existante sans marqueur ⇒ aucune écriture ; cible archive pointée sur une table marquée DLNUF ⇒ aucune écriture et message « créer une nouvelle table » dans les deux cas ; table DLNUF avec colonne `file` ⇒ aucune écriture et message « Colonne(s) fichier » ; `build_avis` en DLNUF ⇒ 412 ; `PATCH selection` avec `referentiel=dlnuf` après synchronisation ⇒ 422.

- [ ] **Étape 3 :** lancer — attendu : échec.

- [ ] **Étape 4 :** implémenter le service, les règles du contrôleur, la route et les vues. Les erreurs s'affichent dans `_build_result` en `alert-danger`.

- [ ] **Étape 5 :** relancer — attendu : tout passe.

- [ ] **Étape 6 :** rubocop, lint, commit `feat(schema_builder): choix archive ou DLNUF, marqueur de table et type figé`.

---

### Task 5: alerte unique dans le moteur

**Fichiers :**
- Modifier : `app/lib/verification_service.rb` (`apply_task`)
- Test : `spec/lib/verification_service_spec.rb` (ce fichier a déjà une modification locale non commitée : ne pas l'écraser, y ajouter)

**Interfaces :**
- Consomme : `Referentiel::Verrou::Refus`, `Referentiel::Alerte.signaler`.
- Produit : dans `apply_task`, un `Refus` marque le `Check` en échec (`failed`, `failed_at`), appelle `Alerte.signaler` et **n'appelle pas** `report_error` ; il n'est pas relevé, quel que soit l'environnement. Les autres exceptions gardent leur traitement actuel.

- [ ] **Étape 1 : test** : une tâche `when_ok` dont `process` lève `Referentiel::Verrou::Refus` sur deux dossiers ⇒ deux `Check` en échec, `Referentiel::Alerte` reçoit `signaler` deux fois, `NotificationMailer.report_error` n'est pas appelé par `report_error`.
- [ ] **Étape 2 :** lancer — attendu : échec (l'exception est relevée hors production).
- [ ] **Étape 3 :** ajouter un `rescue Referentiel::Verrou::Refus => e` avant le `rescue StandardError` de `apply_task`.
- [ ] **Étape 4 :** `bundle exec rspec spec/lib/verification_service_spec.rb` — attendu : tout passe.
- [ ] **Étape 5 :** rubocop, lint, commit `feat(verification): un refus de référentiel alerte une fois, sans courriel par dossier`.

---

### Task 6: la synchro lit le type et refuse ce qui le contredit

**Fichiers :**
- Modifier : `app/lib/mes_demarches_to_baserow/sync_coordinator.rb` (`initialize`, `build_field_metadata`, `sync_dossier`, `load_block_field_metadata`), `app/lib/mes_demarches_to_baserow/field_filter.rb` si nécessaire pour exposer le type des colonnes de bloc
- Test : `spec/lib/mes_demarches_to_baserow/sync_coordinator_spec.rb`

**Interfaces :**
- Consomme : `Referentiel::Verrou.mode!`, `Referentiel::Marqueur.reference_pj?`.
- Produit :
  - `SyncCoordinator#mode -> :archive | :dlnuf`, calculé une fois dans `initialize` (c'est le « cache court » du contrat : un coordinateur vit le temps d'une passe sur une démarche).
  - `build_field_metadata` ajoute à chaque colonne `'description'` et `'reference_pj'` (booléen, `Marqueur.reference_pj?(description)`).
  - `@proprietaire` : nom de la colonne dont l'`id` est le propriétaire enregistré (DLNUF seulement).

Règles :

- `initialize` appelle `Verrou.mode!(backend: 'baserow', table_ref: table_id.to_s, description_primaire: <description de la colonne `primary`>, lignes: -> { <nombre de lignes de la table> })`. Le `Refus` se propage.
- En DLNUF, à l'initialisation : une colonne `file` dans la table principale ⇒ `Refus` (« colonne fichier <nom> dans une table DLNUF ») ; propriétaire enregistré ne désignant aucune colonne ⇒ `Refus`.
- En DLNUF, au chargement des colonnes d'une table de bloc : une colonne `file` ⇒ `Refus`.
- En DLNUF, `sync_avis` n'est pas appelé.
- En archive : aucune différence de comportement.

- [ ] **Étape 1 : tests** (API Baserow doublée comme dans la spec existante) :

```ruby
it 'reste en archive sans marqueur et synchronise comme avant'       # mode == :archive, sync_avis appelé
it 'passe en DLNUF quand le marqueur et l\'enregistrement concordent' # mode == :dlnuf
it 'adopte en DLNUF une table marquée qu\'il voit pour la première fois' # enregistrement créé, mode == :dlnuf
it 'refuse une table DLNUF dont le marqueur a été retiré'             # raise_error(Referentiel::Verrou::Refus) à new
it 'refuse une table DLNUF contenant une colonne fichier'             # idem, message /colonne fichier RIB/
it 'refuse une table de bloc DLNUF contenant une colonne fichier'     # à sync_dossier
it 'ne synchronise pas les avis en DLNUF'                             # AvisSyncer jamais instancié
```

- [ ] **Étape 2 :** lancer — attendu : échec.
- [ ] **Étape 3 :** implémenter. Pour `lignes`, une lecture d'une seule ligne suffit (`list_rows` avec `size: 1`, puis le compteur `count` de la réponse).
- [ ] **Étape 4 :** `bundle exec rspec spec/lib/mes_demarches_to_baserow` — attendu : tout passe, anciennes specs comprises.
- [ ] **Étape 5 :** rubocop, lint, commit `feat(baserow_sync): type de table lu au démarrage, refus des tables incohérentes`.

---

### Task 7: e-mail du titulaire en minuscules et références de pièces

**Fichiers :**
- Créer : `app/lib/referentiel/reference_pj.rb`
- Modifier : `app/lib/mes_demarches_to_baserow/data_extractor.rb` (`initialize`, `extract_fields`, `extract_block_rows`), `app/lib/mes_demarches_to_baserow/sync_coordinator.rb` (`sync_dossier`)
- Test : `spec/lib/referentiel/reference_pj_spec.rb`, `spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb`, `spec/lib/mes_demarches_to_baserow/sync_coordinator_spec.rb`

**Interfaces :**
- Consomme : `SyncCoordinator#mode`, `'reference_pj'` des métadonnées (tâche 6).
- Produit :
  - `Referentiel::ReferencePj.pour(numero_dossier, champ) -> String | nil` ; `nil` si le champ n'a aucun fichier.
  - `DataExtractor.new(field_metadata, options, block_columns: nil, referentiel: :archive)`.

L'identifiant GraphQL d'un champ est le Base64 de `Champ-<stable_id>` ou, dans un bloc répétable, de `Champ-<stable_id>|<row_id>` (`Champ#to_typed_id` de Mes-Démarches). `ReferencePj` le décode ; un identifiant qui ne correspond pas à `\AChamp-(\d+)(?:\|([A-Za-z0-9_-]+))?\z` lève `ArgumentError`.

Règles en DLNUF :

- Table principale, champ `PieceJustificativeChamp` : colonne marquée (`'reference_pj'`) ⇒ la référence, ou `nil` si le champ est vide ; colonne non marquée ⇒ champ ignoré avec un `warn`, jamais d'écriture.
- Bloc répétable, champ `PieceJustificativeChamp` : la référence avec `row_id`, ou `nil`.
- Dans `sync_dossier`, après le filtrage des colonnes : `syncable_data[@proprietaire] = dossier.usager&.email&.downcase`.

- [ ] **Étape 1 : tests**

```ruby
# reference_pj_spec.rb
def champ(id_clair, fichiers: [double])
  double(id: Base64.urlsafe_encode64(id_clair, padding: false), files: fichiers, __typename: 'PieceJustificativeChamp')
end

it { expect(Referentiel::ReferencePj.pour(686_128, champ('Champ-155122'))).to eq('md:686128:155122') }
it { expect(Referentiel::ReferencePj.pour(686_128, champ('Champ-155122|01HZX3ABCD'))).to eq('md:686128:155122:01HZX3ABCD') }
it('champ vide') { expect(Referentiel::ReferencePj.pour(686_128, champ('Champ-155122', fichiers: []))).to be_nil }
it('identifiant inattendu') { expect { Referentiel::ReferencePj.pour(1, champ('Dossier-12')) }.to raise_error(ArgumentError) }
```

Dans `data_extractor_spec.rb` (mode `referentiel: :dlnuf`) : PJ avec fichiers sur colonne marquée ⇒ `'md:<n>:<stable_id>'` ; PJ vidée ⇒ `nil` présent dans les données (la cellule sera réinitialisée) ; PJ sur colonne texte non marquée ⇒ clé absente ; PJ dans un bloc ⇒ référence à quatre segments ; en `:archive`, les attentes existantes sur les fichiers sont inchangées.

Dans `sync_coordinator_spec.rb` : en DLNUF, un dossier dont l'usager est `Jean.Dupont@Example.PF` écrit `jean.dupont@example.pf` dans la colonne propriétaire, et aucun appel à `Baserow::FileUploader` n'a lieu ; en archive, l'e-mail est écrit tel quel.

- [ ] **Étape 2 :** lancer — attendu : échec.
- [ ] **Étape 3 :** implémenter. Vérifier d'abord le format de l'identifiant sur un dossier réel de staging (`bin/describe_demarche` ou console) : si le Base64 de l'API porte un remplissage `=`, le décodage doit le tolérer.
- [ ] **Étape 4 :** `bundle exec rspec spec/lib/referentiel spec/lib/mes_demarches_to_baserow` — attendu : tout passe.
- [ ] **Étape 5 :** rubocop, lint, commit `feat(baserow_sync): e-mail du titulaire en minuscules et références de pièces en DLNUF`.

---

### Task 8: hook `deleted` et boucle des suppressions

**Fichiers :**
- Modifier : `app/lib/inspector_task.rb`, `app/lib/mes_demarches.rb` (deux requêtes à côté de `DossiersModifies`), `app/lib/dossier_actions.rb`, `app/lib/verification_service.rb` (`check_demarche`)
- Test : `spec/lib/dossier_actions_spec.rb` (créer si absent), `spec/lib/verification_service_spec.rb`

**Interfaces :**
- Produit :
  - `InspectorTask#deleted(demarche, number)` : ne fait rien par défaut. `demarche` est l'enregistrement `Demarche`, `number` un entier.
  - `MesDemarches::Queries::DossiersEnCorbeille` : `demarche(number:) { pendingDeletedDossiers(deletedSince: $since, after: $cursor) { pageInfo { endCursor hasNextPage } nodes { number } } }`
  - `MesDemarches::Queries::DossiersSupprimes` : même forme sur `deletedDossiers`.
  - `DossierActions.on_deleted_dossiers(demarche_id, since) { |number| }` : parcourt les deux connexions page par page et ne rend chaque numéro qu'une fois.

Règles de la boucle dans `check_demarche`, après `on_dossiers` et avant l'enregistrement de `checked_at`, avec le même `since` :

- Tâches concernées : celles de `controls` et de `@ok_tasks` qui sont valides **et** qui surchargent `deleted` (`task.method(:deleted).owner != InspectorTask`). S'il n'y en a aucune, **aucune requête GraphQL n'est émise**.
- Pour chaque numéro et chaque tâche : `task.deleted(demarche, number)`. Un `Referentiel::Verrou::Refus` ⇒ `Referentiel::Alerte.signaler`, on continue. Une autre exception ⇒ relevée hors production, `report_error('Error applying deleted', e)` en production, on continue avec la tâche suivante.

- [ ] **Étape 1 : tests**

```ruby
# dossier_actions_spec.rb
it 'rend une seule fois un numéro présent dans les deux flux' do
  # pendingDeletedDossiers → [12, 13] ; deletedDossiers → [13, 14], sur deux pages
  expect { |b| DossierActions.on_deleted_dossiers(3604, since, &b) }.to yield_successive_args(12, 13, 14)
end

# verification_service_spec.rb
it 'n\'interroge pas les suppressions quand aucune tâche ne les écoute'
it 'appelle deleted sur chaque tâche qui le surcharge, avec le curseur de la démarche'
it 'continue après une tâche en erreur et avance le curseur'
it 'alerte sans lever quand une tâche refuse'
```

- [ ] **Étape 2 :** lancer — attendu : échec.
- [ ] **Étape 3 :** implémenter. Le schéma GraphQL est chargé par introspection au démarrage : vérifier que les deux requêtes se chargent en console de développement (`MesDemarches::Queries::DossiersSupprimes`) avant de lancer les specs.
- [ ] **Étape 4 :** `bundle exec rspec spec/lib/dossier_actions_spec.rb spec/lib/verification_service_spec.rb` — attendu : tout passe.
- [ ] **Étape 5 :** rubocop, lint, commit `feat(verification): hook deleted alimenté par les dossiers supprimés et en corbeille`.

---

### Task 9: effacement de la ligne et de ses blocs dans Baserow

**Fichiers :**
- Modifier : `app/lib/baserow_sync.rb`, `app/lib/mes_demarches_to_baserow/sync_coordinator.rb`, `app/lib/mes_demarches.rb` (fragment `DossierInfo` : ajouter `dateSuppressionParUsager`)
- Test : `spec/lib/baserow_sync_spec.rb` (créer si absent), `spec/lib/mes_demarches_to_baserow/sync_coordinator_spec.rb`

**Interfaces :**
- Consomme : hook `deleted` (tâche 8), `SyncCoordinator#mode` (tâche 6).
- Produit :
  - `SyncCoordinator#delete_dossier(number) -> Boolean` (vrai si une ligne principale a été effacée).
  - `BaserowSync#deleted(demarche, number)`.

Règles :

- `BaserowSync#deleted` obtient le coordinateur de la démarche comme `process` (extraire la création dans une méthode privée commune) et appelle `delete_dossier`. Le filtre `etat_du_dossier` ne s'applique pas.
- `delete_dossier` rend `false` sans rien faire en archive, et quand aucune ligne ne porte ce numéro.
- Sinon, pour chaque table de l'application (hors table principale) dont la colonne `Dossier` est un `link_row` vers la table principale : effacer les lignes liées à la ligne du dossier (`find_by_link_row_id('Dossier', id)`). Puis effacer la ligne principale. Les lignes de blocs d'abord : une interruption laisse une ligne principale que le rejeu retrouvera.
- Dossier supprimé par l'usager seul (décision 5 bis) : dans `BaserowSync#process`, **avant** le filtre `must_check?`, si le coordinateur est en DLNUF et que `dossier.date_suppression_par_usager` est renseigné, appeler `delete_dossier(dossier.number)` et s'arrêter là. En archive, rien ne change. Le test avant `must_check?` compte : un dossier synchronisé en instruction puis accepté ne passerait plus un filtre `etat_du_dossier: en_instruction`.

- [ ] **Étape 1 : tests**

```ruby
it 'efface la ligne d\'un dossier supprimé par l\'usager en DLNUF, même hors du filtre etat_du_dossier'
it 'synchronise normalement un dossier supprimé par l\'usager en archive'
it 'recrée la ligne quand dateSuppressionParUsager est redevenu vide'
it 'n\'efface rien en archive'
it 'efface les lignes des blocs puis la ligne du dossier en DLNUF'   # ordre vérifié avec .ordered
it 'ne touche pas une table non liée à la table principale'
it 'rend false sans erreur quand le dossier n\'a pas de ligne'
it 'BaserowSync#deleted délègue au coordinateur de la démarche'
```

- [ ] **Étape 2 :** lancer — attendu : échec.
- [ ] **Étape 3 :** implémenter.
- [ ] **Étape 4 :** `bundle exec rspec spec/lib/baserow_sync_spec.rb spec/lib/mes_demarches_to_baserow` — attendu : tout passe.
- [ ] **Étape 5 :** rubocop, lint, commit `feat(baserow_sync): effacement de la ligne et de ses blocs quand le dossier est supprimé (DLNUF)`.

---

### Task 10: « Vider la table » dans le builder

**Fichiers :**
- Modifier : `app/lib/baserow/structure_client.rb`, `app/lib/schema_builders/baserow_target.rb`, `app/controllers/admin/schema_builder_controller.rb`, `config/routes.rb`, `app/views/admin/schema_builder/_main_table_section.html.haml`
- Test : `spec/lib/schema_builders/baserow_target_spec.rb`, spec de requêtes du builder

**Interfaces :**
- Produit :
  - `Baserow::StructureClient#list_row_ids(table_id) -> Array<Integer>` (toutes les pages, 200 par page)
  - `Baserow::StructureClient#delete_rows(table_id, ids)` : `POST /api/database/rows/table/{id}/batch-delete/` avec `{ items: [...] }`, par lots de 200. Vérifier le chemin et la limite dans la documentation d'API de l'instance (Baserow 2.0.6) avant d'écrire le test.
  - `SchemaBuilders::BaserowTarget#vider_table(table_id) -> Integer` (nombre de lignes effacées)
  - Route `POST targets/:target/main_table/vider`, helper `vider_admin_demarche_schema_path`.

Règles de l'action `vider_table` :

- Autorisée seulement si `ReferentielDlnuf#type_lu` de la table principale de la cible vaut `:dlnuf` ; sinon `head :forbidden`. Une table d'archive ne se vide jamais par ce bouton.
- Le curseur remis à `EPOCH` est celui de la démarche **sur ce robot**. Si la synchro tourne sur un autre robot, il faut y lancer l'action (ou y reculer le curseur) : le bouton le rappelle dans son texte d'aide.
- Vide les tables de blocs de la cible (`schema_block_targets.backend_table_id` renseignés), puis la table principale, puis `@demarche.update!(checked_at: DossierActions::EPOCH)`.
- Le bouton porte la confirmation : « Toutes les lignes seront effacées, puis tous les dossiers de la démarche seront retraités au prochain passage du robot, y compris par les autres tâches de sa configuration. Continuer ? »

- [ ] **Étape 1 : tests** : `vider_table` efface 450 identifiants en trois appels de 200, 200 et 50 ; l'action rend 403 sur une table sans marqueur DLNUF ; sur une table DLNUF elle vide blocs puis table principale et remet `checked_at` à `EPOCH`.
- [ ] **Étape 2 :** lancer — attendu : échec.
- [ ] **Étape 3 :** implémenter.
- [ ] **Étape 4 :** relancer — attendu : tout passe.
- [ ] **Étape 5 :** rubocop, lint, commit `feat(schema_builder): vider une table DLNUF et reprendre la démarche depuis le début`.

---

### Task 11: documentation et recette en staging

**Fichiers :**
- Modifier : `app/lib/mes_demarches_to_baserow/README.md`, `docs/CONFIGURATION_GUIDE.md` (section `baserow_sync`)

- [ ] **Étape 1 : documenter** en une section « Référentiel DLNUF » : les deux types, le type figé et ce que fait la synchro en cas de refus, le partage des rôles entre le robot qui construit et celui qui synchronise (décision 2 bis), « Rétablir le marqueur » sur le robot qui a alerté, « Vider la table » à la publication, la table Avis ignorée, et la marche à suivre après une alerte (rétablir, puis reculer `checked_at` à la date indiquée). Aucun nouveau paramètre YAML : le type vient de la table.

- [ ] **Étape 2 : suite complète** : `bundle exec rspec` — attendu : aucun échec nouveau par rapport à `dev`.

- [ ] **Étape 3 : commit** `docs(baserow_sync): référentiel DLNUF`.

- [ ] **Étape 4 : recette manuelle en staging** (après CI verte et robot redéployé ; démarche de test et projet Baserow dédiés) :
  1. Builder : cible Baserow en DLNUF, création de la table principale et d'une table de bloc. Vérifier dans Baserow la description de la colonne `Dossier`, les colonnes de PJ en texte marqué, l'absence de table Avis.
  2. Déposer un dossier de test avec une PJ et une ligne de bloc avec PJ, depuis un compte dont l'adresse se saisit avec des majuscules. Vérifier la ligne : e-mail en minuscules, cellules `md:<n>:<stable_id>` et `md:<n>:<stable_id>:<row_id>`, aucun fichier.
  3. Retirer la PJ du dossier : la cellule se vide au passage suivant.
  4. Modifier le marqueur à la main : un seul courriel d'alerte, plus aucune écriture ; « Rétablir le marqueur », sur le robot de staging qui synchronise, relance la synchro.
  4 bis. Construire une seconde table DLNUF depuis l'environnement de dev, la brancher sur le robot de staging : il l'adopte sans courriel (table vide). Rebrancher sur un autre robot une table déjà remplie : adoption avec un courriel d'information.
  5. Sur une démarche **publiée** de recette : supprimer un dossier en construction côté usager, la ligne et ses blocs disparaissent au passage suivant ; le restaurer côté administration, la ligne revient. Même essai sur un dossier **accepté** supprimé par l'usager seul (décision 5 bis).
  6. « Vider la table » : la table se vide puis se remplit au passage suivant.
  7. Avec la session mes-demarches : le champ « Référentiel de Polynésie » branché sur cette table est servi en DLNUF par le marqueur (PR 0).

---

## Annexe — à transmettre à la session mes-demarches

Amendements du contrat `2026-11-06-contrat-referentiel-dlnuf.md` :

- **§2 et §5.1** : en DLNUF, pas de table Avis.
- **§3.4** : remplacer la partie « La synchro mémorise le type par table » et la procédure de retour à archive par : type déclaré par le marqueur à la création, figé par le robot qui synchronise à sa première lecture ; toute divergence entre marqueur et type enregistré suspend écriture et effacement et alerte ; aucun changement de type, on recrée une table ; le marqueur n'est réécrit que par le bouton « Rétablir le marqueur », sur le robot qui synchronise.
- **§4.2** : préciser que le `row_id` est celui de l'identifiant GraphQL du champ (`Champ-<stable_id>|<row_id>`).
- **§5.2** : l'effacement suit deux flux (`pendingDeletedDossiers` et `deletedDossiers`) et emporte les lignes des tables de blocs ; une table DLNUF contenant une colonne `file` est refusée en entier.
- **§5.2 (suite)** : un dossier portant `dateSuppressionParUsager` voit sa ligne effacée par la synchro, même s'il reste visible de l'administration.
- **§5.3** : en DLNUF, MD ne propose que les lignes dont le dossier source est encore `visible_by_user` pour le titulaire. Depuis la décision 5 bis le robot efface déjà ces lignes ; ce filtre n'est plus qu'une seconde protection, utile entre le clic de l'usager et le passage suivant du robot. À garder ou non, au choix de la session mes-demarches.
- **Table 861 (DJS)** : à recréer en DLNUF par le builder ; elle est aujourd'hui alimentée comme une archive.
