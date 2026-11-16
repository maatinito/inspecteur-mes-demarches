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
  email_instructeur: robot-mes-demarches@administration.gov.pf

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
        # Filtrage par état (optionnel)
        # Synchronise uniquement les dossiers dans ces états
        # Si non spécifié, synchronise tous les états
        etat_du_dossier: [en_instruction, accepte]

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

### Blocs répétables
Tables liées avec structure:
- `Bloc` (formula): "12345-1", "12345-2"...
- `Dossier` (link_row): Lien vers la table principale (limité à un seul lien)
- `Ligne` (number): 1, 2, 3...
- Tous les champs du bloc

**Recherche optimisée** : La synchronisation utilise `find_by_link_row_id` pour récupérer efficacement les lignes d'un bloc liées à un dossier spécifique, en filtrant par l'ID de la row principale (au lieu de filtrer par valeur textuelle).

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
1. `Bloc` (formula, champ primaire): `join(totext(field('Dossier')),'')+'-'+totext(field('Ligne'))`
2. `Dossier` (link_row): Lien vers table principale
   - **Important** : Configuré avec `link_row_multiple_relationships: false` pour garantir qu'un bloc ne pointe que vers un seul dossier
3. `Ligne` (number): Numéro de ligne (1, 2, 3...)
4. Champs du bloc répétable

Ordre de création (via RepetableBlockBuilder):
1. Créer table avec "Bloc" (text temporaire) comme primaire
2. Créer champ "Ligne" (number)
3. Créer lien "Dossier" (link_row avec `link_row_multiple_relationships: false`)
4. Modifier "Bloc" en formula
5. Créer les champs du bloc

Note : `ensure_table_structure` vérifie et corrige automatiquement la configuration des tables existantes, y compris la limitation à un seul lien pour le champ "Dossier".

## Options de configuration

### etat_du_dossier (optionnel)
- Type: String ou Array de Strings
- Filtre les dossiers à synchroniser par état
- États possibles: `en_construction`, `en_instruction`, `accepte`, `refuse`, `sans_suite`
- Si non spécifié: synchronise tous les états
- Exemples:
  - `etat_du_dossier: en_instruction` (un seul état)
  - `etat_du_dossier: [en_instruction, accepte]` (plusieurs états)

**Cas d'usage**:
- Ne pas synchroniser les dossiers classés sans suite: `etat_du_dossier: [en_construction, en_instruction, accepte, refuse]`
- Synchroniser uniquement les dossiers acceptés: `etat_du_dossier: accepte`

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
2. Validation de la structure (primary `Avis` + link_row `Dossier`). Si KO, skip avec warn détaillant la raison.
3. Fetch des avis du dossier via GraphQL (incluant `attachments`).
4. Pour chaque avis, upsert par ID GraphQL.
5. PJ : réutilisation de la déduplication par nom+taille (idem PJ des champs).
6. Suppression des avis orphelins (présents en Baserow mais plus en MD) si `supprimer_orphelins: true` (défaut).

## Référentiel DLNUF

Une table Baserow synchronisée est de l'un des deux types suivants.

- **Archive** (comportement historique) : le robot copie les dossiers, leurs fichiers et leurs avis, et n'efface jamais rien.
- **DLNUF** : la table sert de référentiel partagé (voir le contrat `../mes-demarches/docs/superpowers/specs/2026-11-06-contrat-referentiel-dlnuf.md`, dépôt Mes-Démarches). Une ligne disparaît avec son dossier, aucun fichier n'est copié et la ligne porte l'e-mail du titulaire.

**Aucun paramètre YAML n'est ajouté** : le bloc `baserow_sync` reste identique, le type vient de la table elle-même (marqueur posé sur la description de sa colonne primaire).

### Créer une table DLNUF

Dans le builder (page admin du schéma de la démarche), choisir « DLNUF (effacé avec le dossier) » dans « Type de référentiel » **avant** de créer la table principale. Le builder :

- pose sur la colonne primaire le marqueur de table, deux lignes : une phrase lisible (« Référentiel DLNUF : lignes effacées avec leur dossier… Ne pas modifier la ligne suivante. ») et `mes-demarches: referentiel=DLNUF; proprietaire=<id>`, où `<id>` désigne la colonne « Email usager » ;
- crée les colonnes de pièces jointes en **texte** (et non en fichier), avec la description `mes-demarches: reference=piece_justificative` ;
- ne crée pas la table « Avis » (la section Avis du builder disparaît) ;
- impose la colonne « Email usager », qu'on ne peut pas exclure.

Le type se choisit une fois : le sélecteur est verrouillé dans le builder dès la première construction de la table principale, et il n'existe aucun moyen de changer le type d'une table. Pour passer d'archive à DLNUF (ou l'inverse), créer une nouvelle table.

Le builder lit toujours le type sur la table Baserow, jamais dans sa propre base. Il refuse d'écrire sur une table dont le marqueur est illisible ou ne correspond pas au type de la cible et, en DLNUF, refuse toute table (principale ou de bloc) qui contient une colonne fichier. En DLNUF, une table de bloc existante portant le même nom n'est réutilisée que si c'est une table liée à la table principale (voir plus bas).

### Ce que la synchronisation fait différemment

- **Contrôles au démarrage** : quand un dossier de la table est traité (synchronisation ou effacement), avant toute écriture, le robot lit le marqueur, une fois par passage, et le confronte au type qu'il a enregistré. Il vérifie en DLNUF que la colonne propriétaire existe et qu'aucune colonne fichier n'est présente dans la table principale ni dans les tables de blocs. Un échec **suspend l'écriture et l'effacement pour toute la table** et envoie un courriel (au plus un par table et par 24 h) et un message Sentry.
- **Type figé** : le type est celui du marqueur lors de la première lecture par ce robot ; il est ensuite enregistré dans la table `referentiel_tables` du robot. Une table vide ou une table déjà remplie est adoptée ; une table DLNUF déjà remplie déclenche un courriel d'information (adoption, nombre de lignes présentes). Si le marqueur est illisible dès cette première lecture, la table est refusée et son type reste **inconnu** (jamais figé en archive) jusqu'à ce que le marqueur redevienne lisible : la première lecture lisible l'adopte alors comme une table neuve. « Rétablir le marqueur » ne peut rien pour une table de type inconnu : corriger le marqueur à la main dans Baserow.
- **Pièces jointes** : aucun fichier n'est téléchargé. La cellule contient une référence texte `md:<numéro du dossier>:<stable_id du champ>`, ou `md:<numéro>:<stable_id>:<row_id>` dans un bloc répétable (une référence par cellule). Quand le dossier n'a plus la pièce jointe, la cellule est vidée. Une colonne de pièce jointe sans le marqueur `mes-demarches: reference=piece_justificative` n'est jamais écrite.
- **Propriétaire** : la colonne « Email usager » reçoit toujours l'e-mail du titulaire **en minuscules**.
- **Effacement** : une ligne est effacée, avec toutes les lignes de ses blocs, quand son dossier est supprimé ou mis à la corbeille, **ou** quand l'usager seul l'a supprimé (`dateSuppressionParUsager`), même si le dossier reste visible de l'administration (par exemple un dossier accepté). Ce dernier cas est traité quels que soient l'état du dossier, le filtre `etat_du_dossier` et les contrôles de la configuration. L'effacement est idempotent : une ligne absente n'est pas une erreur. Si le dossier est restauré, la ligne est recréée au passage suivant (la restauration modifie le dossier, qui revient par le curseur), à condition que `baserow_sync` soit déclaré sous `when_ok` et qu'aucun contrôle du dossier ne soit en échec ; un dossier restauré alors que sa suppression était en file d'attente est retiré de la file sans effacement.
- **Écoute des suppressions** : le robot ne demande à Mes-Démarches les dossiers supprimés ou en corbeille que pour une table qu'il a enregistrée en DLNUF ; une démarche synchronisée vers une table archive ne fait aucune requête de plus.
- **Tables de blocs** : ce sont les tables de la même application Baserow dont la colonne `Dossier` est un lien vers la table principale. Toute autre table de l'application n'est jamais touchée par l'effacement ni par « Vider la table ».
- **Avis** : le builder ne crée jamais de table « Avis » en DLNUF et la synchronisation n'y écrit pas. Une table « Avis » existante dont la colonne `Dossier` est liée à la table DLNUF est traitée comme une table liée : refusée si elle contient une colonne fichier, et ses lignes sont effacées avec le dossier.
- Le mode archive est inchangé : copie des fichiers, aucun effacement.

### Après une alerte

Le courriel d'alerte (« Référentiel baserow table N : … ») indique la cause : marqueur illisible, type ou propriétaire modifié, colonne fichier, colonne propriétaire absente. Tant que le refus dure, rien n'est écrit ni effacé pour cette table.

Il n'y a **aucun recul de curseur à faire à la main** : les suppressions dont l'effacement a échoué sont mises en file d'attente (table `suppressions_en_attente`) et rejouées à chaque passage jusqu'à réussite (un seul courriel d'erreur par dossier, au premier échec) ; les dossiers dont l'écriture a été refusée restent en échec et sont rejoués par la reprise habituelle des contrôles en échec : au prochain passage après 8 h, ou au redémarrage du robot.

La marche à suivre :

1. Si une colonne fichier a été ajoutée à la main, la supprimer. Si la colonne propriétaire a été supprimée, la table ne peut pas être réparée (une colonne recréée a un nouvel identifiant, alors que le marqueur et le type figé gardent l'ancien) : construire une nouvelle table.
2. Si la description de la colonne primaire a été modifiée, cliquer sur « Rétablir le marqueur » (voir ci-dessous).
3. Au passage suivant, la table est de nouveau acceptée et l'alerte est réinitialisée. Le robot rejoue seul les suppressions en file d'attente dès ce passage ; les dossiers dont l'écriture a été refusée sont rejoués au prochain passage après 8 h, ou au redémarrage du robot.

### « Rétablir le marqueur »

Bouton du builder, sous la table principale. Il réécrit le marqueur d'après le type **enregistré par le robot sur lequel vous êtes**, en conservant le reste de la description. Il n'apparaît que sur le robot qui synchronise la table (celui qui a un enregistrement pour elle) ; sur un autre robot (dev, staging), il est absent ou répond « table inconnue de ce robot ». Sur une table de type inconnu (marqueur illisible dès la première lecture), il refuse : corriger le marqueur à la main.

### « Vider la table »

Bouton du builder (cible DLNUF avec table principale), à utiliser typiquement à la publication d'une démarche, pour retirer les dossiers de test. Il efface toutes les lignes des tables de blocs liées, puis celles de la table principale, et remet au début le curseur (`checked_at`) de **chaque démarche de ce robot qui alimente la table** (toute entrée de configuration contenant, à n'importe quelle profondeur, un `baserow_sync` vers cette table, plus la démarche de la page) ; le message liste les démarches concernées. Tous leurs dossiers sont resynchronisés au passage suivant, **y compris par les autres tâches de leur configuration**. L'autorisation vient du marqueur lu sur la table (refus si ce n'est pas du DLNUF) ; refus aussi si ce robot a figé la table autrement qu'en DLNUF (archive ou inconnu). Une erreur Baserow en cours d'effacement laisse les curseurs inchangés. On peut l'utiliser pendant un passage en cours : le robot n'écrase pas le curseur déplacé.

### Construire sur un robot, synchroniser sur un autre

Le builder peut tourner sur dev ou staging alors que la synchronisation se fait en production. Le builder ne lit et n'écrit jamais `referentiel_tables` (sauf « Rétablir le marqueur ») : il décide d'après le marqueur de la table. Le robot qui synchronise adopte la table à sa première lecture (sans courriel si elle est vide, avec un courriel d'information si elle contient déjà des lignes). Conséquences :

- « Rétablir le marqueur » se clique sur le robot qui a émis l'alerte.
- « Vider la table » remet les curseurs du robot sur lequel on clique : si la synchronisation tourne sur un autre robot, lancer l'action depuis le builder de celui-là.
- Si l'écriture du marqueur échoue juste après la création d'une table DLNUF, le builder l'indique en nommant la table : la supprimer dans Baserow avant de construire de nouveau (sans marqueur, elle serait lue comme une archive et toute construction serait refusée).
- Une table ne doit être synchronisée que par un seul robot.

### Avant le déploiement

Vérifier que la description de la colonne primaire des tables **déjà synchronisées** ne contient pas de ligne en texte libre commençant par « Mes démarches : » (ou une variante proche : « mes-demarches », « Mes_démarche »…). Une telle ligne serait lue comme un marqueur illisible et la table serait refusée à la première synchronisation.

## Mapping vers une table socle (`mapping:`)

Une table **socle** a des colonnes communes à plusieurs démarches dont les champs portent des libellés différents (« NOM Président(e) », « Nom responsable (*) » → colonne « Représentant nom »). L'appariement par libellé ne convient plus : le bloc `mapping:` déclare, colonne par colonne, d'où vient la valeur.

```yaml
- baserow_sync:
    baserow:
      table_id: 1046
      token_config: 'Financeurs'
    mapping:
      Représentant nom: 140066                            # nombre → stable_id du champ
      Statuts: 140102                                     # pièce jointe → stable_id obligatoire
      Service: DIREN                                      # texte sans accolade → constante
      Représentant fonction: Président                    # constante (rôle imposé par le formulaire)
      Adresse: "{Adresse postale}{, BP ;Boîte postale}"   # gabarit
```

**Deux formes de valeur :**

- **Un nombre** est le `stable_id` d'un champ usager (`bin/describe_demarche <n>` les liste). Il survit au renommage du champ et donne une valeur typée. C'est la **seule forme admise** pour les colonnes fichier, date, nombre, téléphone, booléen, multi-choix ou lien.
- **Un texte** est un gabarit, avec la syntaxe habituelle du robot : `{Champ}`, `{préfixe;Champ;suffixe}` (préfixe et suffixe n'apparaissent que si le champ est rempli), ternaire `{Champ ? oui : non}`. Sans accolade, c'est une **constante** écrite sur toutes les lignes. Le résultat est toujours du texte : admis seulement sur les colonnes texte, texte long, choix unique, e-mail, URL. Un gabarit vide écrit une cellule vide.

**Une constante seulement si le formulaire impose réellement la valeur** : `Service` (aucun champ ne le porte) ou la fonction du représentant quand le formulaire ne demande que le président. Pas pour une démarche dont les porteurs varient (maire, président, directeur).

**Ce que change la présence d'un `mapping:`** (mode exclusif) : seules les colonnes déclarées sont écrites, plus les métadonnées système par leur nom (« Raison sociale », « Numéro TAHITI », « Date de dépôt »…) et, en DLNUF, la colonne propriétaire. Plus aucun appariement par libellé : un champ homonyme d'une colonne non déclarée n'est pas écrit, les annotations privées ne le sont pas non plus, ni les blocs répétables. Un champ connu de la démarche mais absent du dossier (masqué par une condition, ajouté après le dépôt) vide sa colonne.

**Garde-fous, tous non destructifs** : l'entrée est écartée (la colonne n'est jamais écrite) et un avertissement `BaserowSync mapping: démarche <n>, …` est journalisé une fois par passage, sans rien bloquer :

1. colonne absente de la table ;
2. gabarit sur une colonne d'un type non admis ;
3. `stable_id` inconnu des révisions (brouillon et publiée) de la démarche ;
4. `stable_id` d'une annotation privée (le socle ne reprend que ce que l'usager a saisi), ou d'un champ jamais synchronisé (bloc répétable, titre d'identité, titre de section, explication) ;
5. libellé `{…}` d'un gabarit inconnu de la démarche — sans ce contrôle, un champ renommé viderait la cellule en silence. Sont acceptés : le libellé exact (y compris terminé par « ? »), un chemin pointé dont la racine est un libellé (`{N° Tahiti.adresse}`), un attribut du dossier en minuscules (`{number}`, `{demandeur.nom}`) ;
6. texte fait uniquement de chiffres (`"140066"` entre guillemets) : gardé comme constante, mais signalé (« stable_id attendu ? »).

Une valeur ni nombre ni texte (liste, décimal…) est une erreur de configuration du bloc.

**À savoir :** un gabarit peut lire une annotation privée (le moteur de gabarit les trouve), ce qui sort de la règle « socle = saisie usager » ; une colonne composée (adresse + BP) ne se redécoupe pas au préremplissage d'un autre formulaire.

**La table socle ne se construit pas avec le builder**, qui crée une colonne par champ d'une démarche. Elle se crée à la main ou par script, en respectant le contrat DLNUF (marqueur sur la colonne `Dossier`, colonnes de pièces en texte marquées `mes-demarches: reference=piece_justificative`, aucune colonne fichier). Ne jamais pointer le builder sur une table socle : il y ajouterait les colonnes de la démarche sous leurs libellés locaux.

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
