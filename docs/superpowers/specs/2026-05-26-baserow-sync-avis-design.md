# Synchronisation des avis vers Baserow — Design

**Date** : 2026-05-26
**Statut** : Design approuvé, à implémenter
**Plugin concerné** : `baserow_sync` (`app/lib/baserow_sync.rb` + `app/lib/mes_demarches_to_baserow/`)

## Contexte

Le plugin `BaserowSync` synchronise actuellement les dossiers Mes-Démarches vers Baserow :
- champs système (numéro, état, dates, demandeur, labels)
- champs formulaire (saisis par l'usager)
- annotations privées (saisies par l'instructeur)
- blocs répétables (tables liées découvertes par convention de nom)

**Les avis ne sont pas pris en charge** : ni dans `DataExtractor` (`extract_all` retourne `{main_table, repetable_blocks}`), ni dans `SyncCoordinator`.

Cas d'usage moteur (cité par l'utilisateur) : démarches de type permis de construire où plusieurs services administratifs répondent à des demandes d'avis, avec souvent une PJ détaillée (l'avis lui-même en PDF) accompagnée d'une réponse texte courte (« Favorable sous réserves »…). L'application Baserow cible doit permettre de consulter à la fois les réponses textuelles et les pièces jointes.

Un plugin séparé `AvisToBlocRepetable` sait déjà fetcher les avis via GraphQL (sans les PJ) et les écrit dans une annotation de type bloc répétable. Il n'écrit pas vers Baserow.

## Objectif

Ajouter au plugin `BaserowSync` la capacité de synchroniser, pour chaque dossier traité, ses avis vers une table Baserow dédiée nommée `Avis`, en respectant la philosophie du plugin :

- **Convention over configuration** : la structure Baserow EST la configuration ; aucune option YAML supplémentaire.
- **Auto-discovery** : si la table `Avis` existe dans l'application Baserow, on synchronise ; sinon, skip silencieux.
- **Séparation structure/sync** : la création de la table relève d'un builder admin manuel, jamais de la sync.

## Décisions d'architecture (validées en brainstorming)

| # | Décision | Justification |
|---|----------|---------------|
| D1 | Une table Baserow dédiée nommée `Avis`, link_row vers la table principale | Cohérent avec le pattern blocs répétables ; 1 avis = 1 ligne |
| D2 | Convention de nom fixe `Avis` (non configurable) | Aligné avec l'approche zéro-config du plugin |
| D3 | Primary key = ID GraphQL de l'avis (colonne `Avis`, type text) | Stable, unique ; évite la fragilité d'une clé positionnelle |
| D4 | Approche B : catégorie dédiée `avis` parallèle à `repetable_blocks` | Sémantique claire ; logique d'identification spécifique sans abuser de la notion de bloc répétable |
| D5 | Module partagé `MesDemarches::AvisFetcher` (GraphQL) | Mutualisation avec `AvisToBlocRepetable`, évolution unique de la query |
| D6 | `AvisTableBuilder` (manuel via UI admin) | Suit le pattern `SchemaBuilder` / `RepetableBlockBuilder` ; la sync reste passive |
| D7 | Inclusion des pièces jointes (`attachments`) dès la v1 | Cas d'usage moteur ; le type `File` GraphQL est compatible avec `normalize_files` existant |

## Architecture des composants

```
BaserowSync (FieldChecker)                       [inchangé]
└─ MesDemarchesToBaserow::SyncCoordinator        [+ étape sync_avis]
   ├─ DataExtractor                              [+ extract_avis_row]
   ├─ RowUpserter                                [réutilisé tel quel]
   ├─ AvisFetcher (NOUVEAU, partagé)             [GraphQL]
   ├─ AvisSyncer (NOUVEAU)                       [orchestration table Avis]
   └─ AvisTableBuilder (NOUVEAU, hors sync)      [création table via admin UI]
```

**Modules nouveaux** :

1. `app/lib/mes_demarches/avis_fetcher.rb`
   - Méthode `fetch(dossier_number)` → `Array<Avis>`
   - Encapsule la query GraphQL incluant les attachments
   - Gestion d'erreur : log + return `[]` (idem `AvisToBlocRepetable`)
   - Utilisable par `BaserowSync` et `AvisToBlocRepetable` (refactor de ce dernier dans un second temps, hors périmètre v1 strict)

2. `app/lib/mes_demarches_to_baserow/avis_syncer.rb`
   - Découverte de la table `Avis` dans l'application
   - Validation de la structure minimale (primary `Avis`, link_row `Dossier`)
   - Upsert ligne par ligne via `RowUpserter`
   - Suppression des orphelins (lignes de la table Avis liées au dossier mais absentes de la liste courante)

3. `app/lib/mes_demarches_to_baserow/avis_table_builder.rb`
   - Création idempotente de la table `Avis` dans l'application Baserow
   - Workflow `preview` / `build!`, exposé via `Admin::BaserowSchemaController`

## Schéma GraphQL utilisé

Query partagée par `AvisFetcher` :

```graphql
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
```

Notes :
- `attachments` (pluriel) est utilisé exclusivement. Le champ `attachment` (singulier, legacy) est ignoré : `attachments` contient déjà le fichier des anciens avis.
- Type `File` exposé par l'API : `filename`, `byteSize`, `url`, `contentType`, `checksum`, `createdAt`. Seuls les 3 premiers sont nécessaires pour `normalize_files`.

## Structure attendue de la table `Avis` dans Baserow

L'utilisateur (via `AvisTableBuilder` ou manuellement) crée la table avec les colonnes ci-dessous. La sync remplit ce qui existe et ignore le reste.

| Colonne Baserow | Type Baserow | Source MD | Obligatoire ? |
|---|---|---|---|
| `Avis` (**primary**) | text | `avis.id` (ID GraphQL stable) | **Oui** |
| `Dossier` | link_row → table principale, `link_row_multiple_relationships: false` | `existing_row.id` de la table principale du dossier | **Oui** |
| `Question` | long_text | `avis.question` | Non |
| `Réponse` | long_text | `avis.reponse` | Non |
| `Libellé question` | text | `avis.questionLabel` | Non |
| `Réponse fermée` | boolean | `avis.questionAnswer` (Boolean GraphQL) | Non |
| `Date question` | date | `avis.dateQuestion` (formatée via `format_date`) | Non |
| `Date réponse` | date | `avis.dateReponse` | Non |
| `Email expert` | email | `avis.expert&.email` | Non |
| `Email demandeur` | email | `avis.claimant&.email` | Non |
| `Pièces jointes` | file | `avis.attachments` (déduplication par nom+taille via `normalize_files`) | Non |

**Validation** : si `Avis` (primary) ou `Dossier` (link_row vers la bonne table) manque ou n'a pas la bonne configuration, `AvisSyncer` skip avec un warn explicite — pas de tentative de sync.

## Data flow

```
BaserowSync#process(demarche, dossier)
 └─ SyncCoordinator#sync_dossier(dossier)
    1. existing_row = upsert main row                  [existant]
    2. sync repetable blocks                            [existant]
    3. sync_avis(dossier, existing_row)                 [NOUVEAU]
         a. table_avis = find_table_by_name("Avis", application_id)
            └─ return early avec debug log si nil
         b. valide structure minimale (primary + link_row Dossier)
            └─ return early avec warn si non conforme
         c. avis_list = AvisFetcher.fetch(dossier.number)
            └─ return early avec error log si erreur GraphQL
         d. field_metadata_avis = load (caché par démarche)
         e. existing_avis_rows = fetch all rows where Dossier link_row == existing_row.id
         f. pour chaque avis :
              - row_data = DataExtractor.extract_avis_row(avis, field_metadata_avis, existing_row.id, existing_avis_row_for_this_id)
              - RowUpserter.upsert(table_avis, primary_field: "Avis", primary_value: avis.id, data: row_data)
         g. si supprimer_orphelins (défaut true) :
              - orphans = existing_avis_rows.reject { |r| current_avis_ids.include?(r["Avis"]) }
              - delete orphans (batch)
```

**Ordering** : sync avis **après** la table principale (besoin du `existing_row.id` pour le link_row) et **indépendamment** des blocs répétables.

**Caches** :
- `field_metadata` table Avis : chargé une fois par démarche (idem table principale)
- Liste des tables de l'application : déjà cachée dans `SyncCoordinator`
- `existing_avis_rows` : récupérées une fois par dossier (limite filtrée par link_row)

## Réutilisation des PJ — détail

La colonne `Pièces jointes` reçoit la valeur produite par `DataExtractor.normalize_files(attachments_array, existing_files)`. L'objet `File` GraphQL (`filename`, `byte_size`, `url`) a une interface identique à celle déjà utilisée pour les `PieceJustificativeChamp`. Bénéfices acquis sans code supplémentaire :

- Déduplication par (nom + taille) → réutilisation du `name` (hash Baserow) pour les fichiers déjà uploadés, et envoi par `url` pour les nouveaux.
- `visible_name` préservé pour ne pas perdre le nom de fichier d'origine côté Baserow.
- Si aucun fichier nouveau : pas de modification du champ (`nil` retourné).

**Adaptation mineure nécessaire** : `normalize_files` actuel est typé sur un `champ` de type `PieceJustificativeChamp` (utilise `champ.files`). Pour les avis, on reçoit directement une `Array<File>`. Refactor proposé :
- Extraire le cœur de `normalize_files` en une méthode `normalize_file_array(files, existing_files)` qui prend une liste `File` brute.
- La méthode existante `normalize_files(champ, existing_files)` devient un thin wrapper : `normalize_file_array(champ.files, existing_files)`.
- `DataExtractor.extract_avis_row` appelle directement `normalize_file_array(avis.attachments, existing_pjs_from_baserow_row)`.

## `AvisTableBuilder` — création/maj structure

**Module** : `MesDemarchesToBaserow::AvisTableBuilder`

**Interface** :
```ruby
builder = MesDemarchesToBaserow::AvisTableBuilder.new(
  main_table_id,
  application_id,
  workspace_id
)

builder.preview
# => {
#   will_create_table: Boolean,
#   table_name: "Avis",
#   existing_fields: [...],
#   missing_fields: [...]
# }

builder.build!
# => {
#   table_created: Boolean,
#   fields_created: [...],
#   errors: [...]
# }
```

**Comportement `build!`** (idempotent, ne supprime jamais rien) :

1. Cherche la table `Avis` dans l'application.
2. Si absente, crée la table avec primary `Avis` (text).
3. Garantit le champ `Dossier` (link_row vers `main_table_id`, `link_row_multiple_relationships: false`). Si présent mais mal configuré : corrige.
4. Garantit les colonnes standard si absentes : `Question` (long_text), `Réponse` (long_text), `Libellé question` (text), `Réponse fermée` (boolean), `Date question` (date), `Date réponse` (date), `Email expert` (email), `Email demandeur` (email), `Pièces jointes` (file).
5. Ne touche jamais aux colonnes existantes (l'utilisateur peut supprimer ou ajouter des colonnes après).

**Intégration UI admin** :
- Actions `preview_avis_table` et `build_avis_table` ajoutées à `Admin::BaserowSchemaController`.
- Réutilise la vue `repetable_blocks.html.haml` (section dédiée « Table Avis »), pour éviter une nouvelle page.
- Bouton « Créer/mettre à jour la table Avis » → preview → confirmation → build.

## Edge cases et gestion d'erreurs

| Situation | Comportement |
|---|---|
| Table `Avis` n'existe pas dans Baserow | Skip silencieux (`debug` log : `BaserowSync.avis: table 'Avis' absente, skip`) |
| Dossier sans avis (`avis_list == []`) | Pas d'upsert ; si `supprimer_orphelins: true`, suppression des anciennes lignes orphelines |
| Avis sans réponse (en attente d'expert) | Sync avec `Réponse=null`, `Date réponse=null` — miroir exact |
| Expert ou claimant null (compte supprimé) | Sync avec emails à `null`, pas d'erreur |
| Avis sans attachments | Champ `Pièces jointes` non envoyé |
| Erreur GraphQL `AvisFetcher.fetch` | Log error + `return []`. La sync de la table principale et des blocs n'est pas annulée. |
| Erreur Baserow upsert d'un avis | Retry standard (backoff). Si `continuer_si_erreur: true`, on continue les autres avis. |
| Structure table non conforme (pas de primary `Avis` ou pas de link_row `Dossier`) | Skip + warn explicite avec détail de l'incohérence |
| Avis ID modifié côté MD (théorique) | L'ancien devient orphelin → supprimé si `supprimer_orphelins: true` |
| PJ ajoutée depuis le dernier sync | Upload via URL (retry standard) |
| PJ supprimée côté avis MD | La liste envoyée à Baserow ne la contient plus → disparaît de la cellule |
| Limitation réseau k8s pour téléchargement PJ | Même limitation que pour les PJ des champs (déjà documentée dans le README) |

**Logging clé** :
- Démarrage : `BaserowSync.avis: N avis à synchroniser pour dossier X`
- Skip table absente : `BaserowSync.avis: table 'Avis' absente, skip`
- Structure invalide : `BaserowSync.avis: structure invalide (raison) — skip`
- Fin : `BaserowSync.avis: N synchronisés, M orphelins supprimés`

## Tests

| Fichier | Couverture |
|---|---|
| `spec/lib/mes_demarches/avis_fetcher_spec.rb` | Query GraphQL, gestion d'erreur réseau, dossier sans avis, avis avec/sans attachments |
| `spec/lib/mes_demarches_to_baserow/data_extractor_spec.rb` | `extract_avis_row` : tous les champs, normalisation dates, normalisation files (avec dedup) |
| `spec/lib/mes_demarches_to_baserow/avis_syncer_spec.rb` | Découverte de table, structure invalide, upsert, orphelins, dossier sans avis |
| `spec/lib/mes_demarches_to_baserow/avis_table_builder_spec.rb` | Preview, build, idempotence, mise à niveau d'une table existante |
| `spec/lib/mes_demarches_to_baserow/sync_coordinator_spec.rb` | Enchaînement `sync_avis` après `sync_main_row` |
| `spec/lib/baserow_sync_spec.rb` | End-to-end avec WebMock : dossier avec 2 avis + PJ → 2 lignes Avis créées avec PJ uploadées |

**Patterns à suivre** :
- Mocks GraphQL : identiques à `spec/lib/avis_to_bloc_repetable_spec.rb`
- Mocks Baserow : identiques aux specs `mes_demarches_to_baserow/` existantes
- Pour les fixtures GraphQL d'avis avec attachments, créer un nouveau fixture (`spec/fixtures/graphql/dossier_avis_with_attachments.json`)

## Hors périmètre v1

- Sync vers plusieurs tables `Avis` distinctes (par expert, par groupe…)
- Historique des modifications d'avis (chaque sync écrase la dernière version connue)
- Refactor de `AvisToBlocRepetable` pour utiliser `AvisFetcher` partagé (peut être fait en suivi, sans risque pour ce design)
- Sync des `instructeur` sur l'avis (champ disponible mais redondant avec les autres données)

## Critères de succès

1. Une table `Avis` créée via le builder admin a la structure attendue.
2. Un dossier avec 3 avis (1 sans réponse, 1 avec réponse texte, 1 avec réponse texte + 2 PJ) produit 3 lignes Baserow avec données correctes et PJ uploadées.
3. Re-sync du même dossier sans changement n'upload aucune PJ supplémentaire (dedup nom+taille).
4. Suppression d'un avis côté MD → ligne supprimée de Baserow (avec `supprimer_orphelins: true`).
5. Aucune régression sur les tests existants du plugin `baserow_sync`.
6. La sync d'un dossier sans table `Avis` configurée se déroule sans erreur (skip silencieux).
