# Builder Schema — Diff & Exclusion (extension Slice 1)

**Date** : 2026-05-29
**Auteur** : Christian Lautier (brainstorming avec Claude)
**Statut** : Design validé — en attente de plan d'implémentation
**Branche cible** : `feature/ui-refonte`

## Contexte

Le Slice 1 de la [refonte UI](2026-05-28-ui-refonte-design.md) a livré un dashboard Hotwire scopé démarche, avec sections Table principale / Avis / Blocs, et un cycle Preview/Build par section.

Trois fonctions manquent par rapport à l'ancien builder Baserow, identifiées en QA manuelle :

1. **Diff-only preview** : actuellement l'aperçu liste tous les champs syncs, peu importe qu'ils existent déjà à la cible. L'ancien builder n'affichait que les champs manquants ou différents.
2. **Exclusion sélective de champs** : aujourd'hui Build pousse tout. L'utilisateur veut pouvoir décocher certains champs avant Build, et que ce choix **persiste** entre les sessions.
3. **Exclusion de blocs entiers** : il est fréquent qu'un bloc répétable n'ait pas vocation à être synchronisé. Aujourd'hui le seul recours est de ne pas cliquer Build.

## Workflow utilisateur cible (validé)

Le scénario dominant est : *"un nouveau champ a été ajouté côté mes-démarches.gov.pf, je reviens sur le dashboard, je veux voir ce nouveau champ et le synchroniser en un clic, sans avoir à redécocher les 3 champs que j'avais décidé d'ignorer la fois précédente."*

C'est ce workflow qui pilote toutes les décisions d'ergonomie ci-dessous.

## Objectifs

1. **Diff-only au load** : à l'ouverture du dashboard, chaque section calcule et affiche automatiquement ce qui diffère entre la démarche MD et la cible Baserow/Grist.
2. **Persistance des exclusions** par démarche-cible, sans nécessiter de query SQL (stockage JSON suffisant).
3. **Granularité d'exclusion à 2 niveaux pour les blocs** : un bloc entier OU un champ dans un bloc.
4. **Pas de friction au premier Build** : tout est coché par défaut, l'utilisateur peut décocher avant de cliquer.

## Design

### 1. Modèle de données

Deux nouvelles colonnes JSON :

```ruby
# Migration 1 — sur schema_targets
add_column :schema_targets, :excluded_field_ids, :jsonb, default: [], null: false
add_column :schema_targets, :excluded_block_descriptor_ids, :jsonb, default: [], null: false

# Migration 2 — sur schema_block_targets
add_column :schema_block_targets, :excluded_field_ids, :jsonb, default: [], null: false
```

Sémantique :
- `schema_targets.excluded_field_ids` → liste des `champ_descriptor.id` Mes-Démarches à ignorer pour la table principale
- `schema_targets.excluded_block_descriptor_ids` → liste des `RepetitionChampDescriptor.id` (blocs entiers) à ignorer
- `schema_block_targets.excluded_field_ids` → liste des `champ_descriptor.id` à ignorer DANS un bloc précis

Type `jsonb` plutôt que `json` pour bénéficier de l'opérateur `?` éventuel et de la validation de structure. Pas de query attendue dessus mais c'est gratuit.

### 2. Calcul du diff (côté serveur)

Nouveau service `SchemaBuilders::Differ` (ou méthode dans les builders existants — à valider en plan).

Pour une section donnée (main_table ou un bloc), le diff produit 4 collections :

```ruby
{
  to_add:     [...],  # champs MD présents, absents de la cible, non-exclus
  to_modify:  [...],  # champs MD présents avec divergence type/options, non-exclus
  ok:         [...],  # champs MD présents et conformes à la cible
  excluded:   [...]   # champs MD listés dans excluded_field_ids
}
```

Pour les blocs, structure agrégée :

```ruby
{
  blocks_excluded:   [...],  # blocs entiers ignorés
  blocks: [
    {
      block_descriptor_id: ...,
      table_name: ...,
      excluded: false,
      diff: { to_add: [...], to_modify: [...], ok: [...], excluded: [...] }
    },
    ...
  ]
}
```

**Comparaison** : nom + type + options de dropdown. C'est tout. Pas de comparaison sur les labels (qui peuvent être édités à la main en cible sans qu'on s'en soucie).

**Champs orphelins en cible** (existent en Baserow/Grist mais pas en MD) : ignorés silencieusement — c'est le cas du renommage manuel (limitation acceptée, futur chantier).

### 3. Affichage diff (Turbo Frame lazy)

Chaque section devient un Turbo Frame avec `src` pointant vers son endpoint de preview, et `loading="lazy"`. Au load du dashboard, l'utilisateur voit un spinner par section, puis le diff apparait en background.

Maquette section principale :

```
┌─ Table principale ────────────────────────────────────────┐
│ Statut : sync OK le 2026-05-15                            │
│                                                            │
│ 🟢 À ajouter (2)                                          │
│   ☑ adresse_postale (text)                                │
│   ☑ telephone_secondaire (phone_number)                   │
│                                                            │
│ 🟡 À modifier (1)                                         │
│   ☑ situation_familiale : dropdown                        │
│     ↳ +2 options : "Divorcé", "Veuf"                      │
│                                                            │
│ ▶ 23 champs conformes (cliquer pour déplier)              │
│                                                            │
│ ⛔ Ignorés (3)                                            │
│   ☐ observation_libre                                     │
│   ☐ commentaire_agent                                     │
│   ☐ date_creation_dossier                                 │
│                                                            │
│ [Synchroniser 3 champs cochés]                            │
└────────────────────────────────────────────────────────────┘
```

État initial des cases :
- "À ajouter" / "À modifier" → **coché** (default = on synchronise)
- "Ignorés" → **décoché** (on ne synchronise pas)
- "OK" → caché derrière un toggle "déplier" (pas de checkbox visible — c'est conforme, rien à faire)

Cocher/décocher = action atomique. PATCH endpoint qui met à jour `excluded_field_ids`, puis renvoie un Turbo Stream qui replace la section entière avec le diff recalculé. Le champ bascule visuellement entre "À ajouter/modifier" et "Ignorés".

Maquette section blocs (2 niveaux) :

```
┌─ Blocs répétables ────────────────────────────────────────┐
│ ☑ Membres du bureau (table)                               │
│   ├─ 🟢 À ajouter (1) : ☑ telephone                       │
│   └─ ▶ 5 champs conformes                                 │
│                                                            │
│ ☑ Pièces jointes (table)                                  │
│   └─ 🟢 À ajouter (3) : ☑ doc_1, ☑ doc_2, ☑ doc_3        │
│                                                            │
│ ☐ Activités annexes (bloc entier ignoré)                  │
│                                                            │
│ [Synchroniser]                                            │
└────────────────────────────────────────────────────────────┘
```

- Checkbox au niveau du bloc → toggle dans `schema_targets.excluded_block_descriptor_ids`
- Bloc décoché → bloc complet ignoré, son diff interne n'est pas affiché
- Bloc coché → on voit son diff interne, avec checkboxes par champ → toggle dans `schema_block_targets.excluded_field_ids`

### 4. Endpoints

Nouveaux endpoints REST sur `Admin::SchemaBuilderController` :

```ruby
# Toggle un champ de la table principale
PATCH /admin/demarches/:demarche_id/schema/targets/:target/main_table/fields/:field_id/exclusion
  body: { excluded: true|false }

# Toggle un bloc entier
PATCH /admin/demarches/:demarche_id/schema/targets/:target/blocks/:block_id/exclusion
  body: { excluded: true|false }

# Toggle un champ DANS un bloc
PATCH /admin/demarches/:demarche_id/schema/targets/:target/blocks/:block_id/fields/:field_id/exclusion
  body: { excluded: true|false }
```

Chacun renvoie un Turbo Stream qui replace la section concernée avec son diff recalculé.

### 5. Build modifié

Les actions `build_main_table`, `build_blocks` existantes sont mises à jour pour respecter les exclusions :

- `MainTableBuilder.build!` filtre les champs par `excluded_field_ids` avant d'appeler `target.create_table/update_fields`
- `BlockBuilder.build!` saute les blocs dont l'ID est dans `excluded_block_descriptor_ids`, et pour les autres filtre les champs par `excluded_field_ids` sur leur `SchemaBlockTarget`

Le bouton Build affiche dynamiquement le compteur : "Synchroniser X champs cochés", désactivé si X = 0.

### 6. Initialisation des SchemaBlockTarget

Aujourd'hui, `SchemaBlockTarget` est créé seulement après un Build de blocs réussi. Or pour stocker les exclusions DANS un bloc, il faut un enregistrement avant même le premier Build.

Décision : **autocréer** un `SchemaBlockTarget` à la première lecture du diff bloc (lazy, dans le service `Differ`). Le `backend_table_id` reste `nil` jusqu'au Build. C'est juste un porteur d'état pour les exclusions.

## Hors scope (chantier futur)

1. **Matching par field_id Baserow stocké** : permettrait de détecter les renommages manuels dans Baserow. Nécessite de stocker en local les IDs externes des champs, pas juste leurs noms. Chantier dédié.
2. **Diff sur les labels** : non considéré comme une divergence à signaler. L'utilisateur reste libre de renommer dans Baserow sans que ça déclenche un "à modifier".
3. **Bulk actions** : "tout cocher / tout décocher". Pas demandé, à ajouter si besoin émerge.
4. **Section Avis** : schéma fixe (6 champs), pas de notion d'exclusion. Inchangée.

## Risques et mitigations

| Risque | Mitigation |
|---|---|
| Calcul du diff = N+1 appels API par section au load | Cache léger par requête (mémoriser la liste des champs cible pour la durée du request cycle). Si vraiment lent, fragment cache Rails sur 30s. |
| Migration de `schema_block_targets` rétrocompatible | `excluded_field_ids` default `[]` not null → tous les enregistrements existants ont une liste vide → compatible. |
| Race condition sur le toggle (utilisateur clique vite plusieurs cases) | Chaque PATCH est atomique (un seul `update!`). Les Turbo Stream qui arrivent dans le désordre afficheront chacun un état cohérent. Pas de blocage utilisateur. |
| Premier Build avec tout coché peut créer des champs qu'on regrettera | C'est exactement le comportement actuel (Build pousse tout) → pas de régression. L'utilisateur peut décocher avant de cliquer s'il veut éviter. |

## Décisions clés (récapitulatif)

| Décision | Valeur |
|---|---|
| Stockage exclusions | JSON (`jsonb`) sur 2 colonnes des modèles existants |
| Comparaison diff | Nom + type + options dropdown ; pas les labels |
| Champs orphelins cible (custom Baserow) | Ignorés, jamais affichés |
| Initialisation `SchemaBlockTarget` | Autocréée au premier preview, `backend_table_id` nullable |
| Chargement preview | Turbo Frame lazy au load du dashboard |
| Toggle exclusion | PATCH endpoint atomique + Turbo Stream replace section |
| Builds respectent les exclusions | Filtrage dans les builders avant appel adapter |
| Renommage manuel détecté | Non — limitation acceptée, chantier futur |
