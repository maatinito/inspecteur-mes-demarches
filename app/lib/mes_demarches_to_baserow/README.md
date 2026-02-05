# BaserowSync - Synchronisation automatique Mes-Démarches → Baserow

## Vue d'ensemble

BaserowSync est un `InspectorTask` qui synchronise automatiquement les dossiers de Mes-Démarches vers des tables Baserow. Il s'intègre dans le système VerificationService existant et s'exécute pour chaque dossier traité.

## Architecture

```
BaserowSync (InspectorTask)
├─ SyncCoordinator: Orchestre la synchronisation
├─ DataExtractor: Extrait les données du dossier
├─ FieldFilter: Filtre les champs read-only
└─ RowUpserter: Insert/update dans Baserow
```

## Configuration YAML

### Configuration minimale

```yaml
ma_procedure:
  demarches: [1234]
  email_instructeur: admin@example.com

  when_ok:
    - baserow_sync:
        baserow:
          table_id: 42
          token_config: 'tftn'  # Optionnel

# C'est tout ! Tout est auto-découvert depuis Baserow
```

### Configuration avec options avancées

```yaml
ma_procedure:
  demarches: [1234]

  when_ok:
    - baserow_sync:
        baserow:
          table_id: 100
          token_config: 'ma_config'

        options:
          continuer_si_erreur: true    # Continue même si un dossier échoue
          supprimer_orphelins: true    # Supprimer les lignes orphelines (miroir exact)
          tentatives: 3                # 3 tentatives en cas d'erreur
          delai_retry: 5               # Délai initial entre tentatives (secondes)
```

## Données synchronisées

### Champs système (si `include_system_fields: true`)
- Numéro de dossier
- État (brouillon, en_construction, en_instruction, accepte, refuse, etc.)
- Dates (dépôt, passage en instruction, traitement)
- Email usager
- Informations demandeur (civilité, nom, prénom, SIRET)

### Champs formulaire
Tous les champs du formulaire usager présents dans la table Baserow.

### Annotations privées (si `include_annotations: true`)
Toutes les annotations privées instructeur présentes dans la table Baserow.

### Blocs répétables (si `include_repetable_blocks: true`)
Tables liées avec structure:
- `Bloc` (formula): "12345-1", "12345-2"...
- `Dossier` (link_row): Lien vers la table principale
- `Ligne` (number): 1, 2, 3...
- Tous les champs du bloc

## Philosophie : Convention over Configuration

**Principe fondamental** : **Si un champ ou une table existe dans Baserow, on le synchronise. Sinon, on l'ignore.**

Cette approche élimine toute configuration complexe :
- ✅ Pas de liste de champs à spécifier
- ✅ Pas d'options `include_system_fields`, `include_annotations`, `include_repetable_blocks`
- ✅ Pas d'IDs GraphQL ou Baserow à connaître
- ✅ La structure Baserow **EST** la configuration

### Auto-découverte complète

#### Champs de la table principale
1. Extraction de TOUTES les données du dossier :
   - Champs système (Dossier, État, Dates, Usager, etc.)
   - Champs formulaire (saisis par l'usager)
   - Annotations privées (saisies par l'instructeur)

2. Chargement des métadonnées de la table Baserow

3. Filtrage : seuls les champs **présents dans Baserow** sont synchronisés
   - Champ "État" existe dans Baserow → synchronisé ✅
   - Champ "Commentaire interne" n'existe pas dans Baserow → ignoré ⏭️

4. Exclusion automatique des champs read-only (formula, lookup, rollup)

#### Blocs répétables

- **Convention de nommage** : Bloc "Bénéficiaires" dans Mes-Démarches → Table "Bénéficiaires" dans Baserow

- **Découverte automatique** :
  1. Récupération de l'`application_id` depuis la table principale
  2. Liste de toutes les tables de l'application Baserow
  3. Pour chaque bloc répétable du dossier : recherche d'une table avec le même nom
  4. Si table trouvée → synchronisation ✅
  5. Si table non trouvée → skip silencieux (log debug) ⏭️

**Résultat** : Ajoutez/supprimez des champs ou tables dans Baserow, la synchronisation s'adapte automatiquement. Aucun changement de configuration nécessaire !

## Fonctionnement

### 1. Filtrage des champs

La synchronisation se base sur ce qui existe dans Baserow:
- Seuls les champs présents dans Baserow sont synchronisés
- Les champs read-only sont automatiquement exclus:
  - `formula`: Champs calculés
  - `lookup`: Recherches depuis tables liées
  - `rollup`: Agrégations
  - `count`: Compteurs
  - `created_on`, `last_modified`: Champs système

### 2. Normalisation des valeurs

Les valeurs sont normalisées selon le type Baserow:

| Type Mes-Démarches | Type Baserow | Normalisation |
|-------------------|--------------|---------------|
| DateChamp | date | ISO8601 → YYYY-MM-DD |
| CheckboxChamp | boolean | "Oui"/"Non" → true/false |
| DropDownListChamp | single_select | Valeur texte |
| DropDownListChamp (avec otherOption) | text | Valeur texte |
| MultipleDropDownListChamp | multiple_select | Array de valeurs |
| PieceJustificativeChamp | file | Array de {name, url} |
| IntegerNumberChamp | number | String → Float |

### 3. Stratégie d'update

**Update complet**: Tous les champs sont envoyés à chaque synchronisation, même si les valeurs n'ont pas changé.

Avantages:
- Implémentation simple
- Pas de fetch supplémentaire avant update
- Garantit la cohérence des données

Inconvénients:
- Peut créer des logs d'activité même sans changement réel

### 4. Gestion des erreurs

- **Retry automatique** avec backoff exponentiel (2s, 4s, 8s...)
- **Erreurs retryables**: Timeout (408), Rate limit (429), Erreurs serveur (500-504)
- **Option `continuer_si_erreur`**: Continue la synchronisation même si un dossier échoue
- **Logging**: Tous les échecs sont loggés et envoyés à Sentry

## Structure des tables Baserow

### Table principale

Doit contenir au minimum:
- Champ `Dossier` (number ou text): Identifiant unique du dossier

Peut contenir:
- Tous les champs système (État, dates, usager...)
- Tous les champs du formulaire
- Toutes les annotations privées

### Tables blocs répétables

Structure requise:
1. `Bloc` (formula, champ primaire): `concat(join('Dossier',''),"-",totext(field('Ligne')))`
2. `Dossier` (link_row): Lien vers table principale
3. `Ligne` (number): Numéro de ligne (1, 2, 3...)
4. Champs du bloc répétable

Ordre de création (via RepetableBlockBuilder):
1. Créer table avec "Bloc" (text temporaire) comme primaire
2. Créer champ "Ligne" (number)
3. Créer lien "Dossier" (link_row)
4. Modifier "Bloc" en formula
5. Créer les champs du bloc

## Options de configuration

### baserow (requis)
- `table_id` (requis): ID de la table Baserow principale
- `token_config` (optionnel): Nom de la config de token dans la table BASEROW_TOKEN_TABLE

### options (toutes optionnelles)
- `continuer_si_erreur`: Continuer si un dossier échoue (true/false, défaut: false)
- `tentatives`: Nombre de tentatives en cas d'erreur (défaut: 3)
- `delai_retry`: Délai initial entre tentatives en secondes (défaut: 5)
- `supprimer_orphelins`: Supprimer les lignes orphelines de blocs répétables (true/false, **défaut: true**)

#### Option `supprimer_orphelins` (blocs répétables)

**Philosophie** : Baserow est un **miroir exact** de Mes-Démarches (archive pour visualisation). Les suppressions dans Mes-Démarches doivent être reflétées dans Baserow.

**Exemple** :
```
État initial Baserow (dossier 12345, bloc "Bénéficiaires") :
- 12345-1 : Alice
- 12345-2 : Bob
- 12345-3 : Charlie

L'usager supprime Charlie du dossier.

Avec supprimer_orphelins: true (défaut, recommandé) :
- 12345-1 et 12345-2 sont mis à jour
- 12345-3 est supprimée de Baserow → Miroir exact ✅

Avec supprimer_orphelins: false :
- 12345-1 et 12345-2 sont mis à jour
- 12345-3 reste dans Baserow (orpheline) → Données obsolètes ⚠️
```

**Recommandation** : **Laisser à `true` (défaut)** pour garantir que Baserow reflète exactement l'état actuel de Mes-Démarches. Ne passer à `false` que si vous avez besoin de conserver l'historique complet (y compris les lignes supprimées).

**Note** : Les options `include_system_fields`, `include_annotations`, `include_repetable_blocks` et `repetable_blocks` sont **obsolètes** et ignorées. Tout est auto-découvert depuis Baserow.

## Intégration avec VerificationService

Aucune modification de VerificationService n'est nécessaire. Il suffit d'ajouter la configuration dans le fichier YAML:

```yaml
ma_procedure:
  demarches: [1234]
  controles: [...]

  when_ok:
    - baserow_sync: { ... }
```

VerificationService appellera automatiquement `BaserowSync.process(demarche, dossier)` pour chaque dossier validé.

## Gestion intelligente des fichiers

### Détection des fichiers existants

Le système compare les fichiers par **nom ET taille** pour éviter les re-téléchargements inutiles:

1. Lors de la synchronisation, récupération de la row existante dans Baserow
2. Extraction de la liste des fichiers déjà uploadés (nom + taille en octets)
3. Comparaison avec les fichiers du dossier Mes-Démarches
4. Envoi uniquement des **nouveaux fichiers** (absents de Baserow ou taille différente)

**Important**:
- Les URLs Mes-Démarches changent à chaque requête (tokens temporaires)
- La comparaison se fait sur le **nom ET la taille du fichier**
- Si un fichier a le même nom mais une taille différente, il est considéré comme nouveau (cas d'une modification)
- Baserow ne fournit pas de checksum, donc la taille est le meilleur indicateur disponible

### Exemple

```
État initial Baserow:
- doc1.pdf (1024 octets, déjà uploadé)
- doc2.pdf (2048 octets, déjà uploadé)

Dossier Mes-Démarches:
- doc1.pdf (1024 octets, URL: https://md.gp.pf/...?token=abc123)
- doc2.pdf (2048 octets, URL: https://md.gp.pf/...?token=def456)
- doc2.pdf (3000 octets, URL: https://md.gp.pf/...?token=xyz789)  ← Modifié
- doc3.pdf (4096 octets, URL: https://md.gp.pf/...?token=ghi789)  ← Nouveau

Résultat de la synchro:
→ Envoi de doc2.pdf (taille différente, fichier modifié)
→ Envoi de doc3.pdf (nouveau fichier)
→ doc1.pdf reste en place (identique)
```

### Limitations connues

**Problème réseau k8s**: Baserow peut avoir des difficultés à accéder aux URLs Mes-Démarches depuis l'environnement k8s.

**Solution future** (si le problème persiste):
1. Téléchargement des fichiers depuis Mes-Démarches vers le serveur
2. Upload direct vers Baserow via multipart/form-data

### DropDownList avec "autre option"

Les dropdowns qui permettent à l'usager d'entrer une valeur personnalisée sont automatiquement détectés via `otherOption: true` dans GraphQL et mappés vers un champ `text` au lieu de `single_select`.

## Tests

```bash
# Tests unitaires
bundle exec rspec spec/lib/baserow_sync_spec.rb
bundle exec rspec spec/lib/baserow_sync/

# Test manuel
rails runner "
  demarche = Demarche.find_by(number: 1234)
  dossier = DossierActions.fetch_dossier(12345)

  params = {
    baserow: { table_id: 42 },
    options: { include_system_fields: true }
  }

  BaserowSync.new(params).process(demarche, dossier)
"
```

## Dépannage

### Erreur "Configuration 'baserow.table_id' manquante"
Vérifier que la config YAML contient bien `baserow: { table_id: ... }`.

### Erreur "Unknown alias"
Si vous utilisez des références YAML (`&name`, `*name`), charger le fichier avec:
```ruby
YAML.load_file(file_path, aliases: true)
```

### Champs formula écrasés
Les champs formula/lookup/rollup sont automatiquement exclus de la synchronisation. Si un champ est écrasé, vérifier qu'il n'est pas de type `text` dans Baserow.

### Blocs répétables non synchronisés
Vérifier que:
- `include_repetable_blocks: true` est présent
- `repetable_blocks` contient les bonnes configs
- Les tables Baserow ont la structure requise (Bloc, Dossier, Ligne)

## Maintenance

### Ajout d'un nouveau type de champ

1. Modifier `TypeMapper.map_field_type` pour mapper le type Mes-Démarches → Baserow
2. Modifier `DataExtractor.normalize_value` pour normaliser les valeurs
3. Ajouter des tests

### Modification de la structure des tables

Utiliser `RepetableBlockBuilder` pour créer/mettre à jour les tables:
```ruby
builder = MesDemarchesToBaserow::RepetableBlockBuilder.new(
  structure_client,
  main_table_id,
  application_id,
  workspace_id
)

report = builder.process_repetition_champs(demarche_revision)
```
