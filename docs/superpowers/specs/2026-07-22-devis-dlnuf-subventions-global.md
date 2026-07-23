# Devis — « Dites-le-nous une fois » sur les démarches de subvention

**Date :** 2026-07-22
**Statut :** devis figé (design verrouillé en brainstorming, prêt pour plan d'implémentation)
**Objet :** mettre en place le « Dites-le-nous une fois » (DLNUF) entre les démarches de
subvention aux associations, autour d'un **référentiel socle commun Baserow** : alimentation
depuis N démarches, mode DLNUF sur le référentiel de Polynésie, et préremplissage (champs +
pièces jointes) dans toutes les démarches.
**Contexte métier :** `docs/cadrage-coordination-subventions-associations.md`,
`docs/grille-fusion-champs-subventions.md`,
`docs/superpowers/specs/2026-06-26-outil-vocabulaire-commun-subventions-design.md`.

---

## 1. Contexte

Plusieurs services ont créé, chacun de leur côté, des démarches de demande de subvention aux
associations sur **mes-démarches.gov.pf**. L'usager y redonne à chaque fois les mêmes données
d'identité (raison sociale, siège, bureau, coordonnées bancaires, pièces juridiques…). L'objectif
est de **ne le demander qu'une fois** : ce que l'association a déjà saisi sur une démarche est
proposé en préremplissage sur les suivantes.

Le pivot technique est un **référentiel socle Baserow** qui sert de **vocabulaire commun** entre
des démarches qui n'ont ni les mêmes champs ni les mêmes libellés. Le projet se décompose en
deux moitiés symétriques autour de ce socle :

```
  [N démarches]  --écriture (synchro)-->  [Table socle Baserow]  --lecture (prefill)-->  [N démarches]
       MD                                  1 ligne / dossier                                    MD
                                          scopée e-mail titulaire
```

- **Écriture** : la synchro `mes_demarches_to_baserow` recopie les données de chaque dossier
  dans le socle.
- **Lecture** : le champ `referentiel_de_polynesie` détecte le mode DLNUF, propose les données
  de l'usager et préremplit champs et pièces jointes.

Deux contraintes déterminantes, propres à la moitié écriture, structurent le devis :

1. **Le mapping.** La synchro actuelle apparie les données **par libellé exact** de champ
   (`app/lib/mes_demarches_to_baserow/data_extractor.rb:146` — `field_name = champ.label ;
   next unless @field_metadata.key?(field_name)`). Il n'existe **aucune couche de mapping**.
   Or une **table socle unique** à colonnes canoniques doit être alimentée par N démarches aux
   **libellés divergents** : l'appariement par libellé ne peut pas fonctionner.

2. **La suppression / RGPD.** Sur la table principale, `RowUpserter` ne fait que create/update —
   **jamais** de delete (le `supprimer_orphelins` ne concerne que les lignes de blocs
   répétables). Une ligne dossier persiste donc indéfiniment dans Baserow. Comme le socle
   devient un *system-of-record* de données personnelles partagées, l'invariant RGPD retenu est
   **durée de vie Baserow = durée de vie Mes-Démarches** : la disparition d'un dossier côté MD
   doit effacer la ligne côté Baserow.

---

## 2. Décisions de design verrouillées

### 2.1 Modèle de données : 1 ligne = 1 dossier, scopée e-mail titulaire

- Une ligne du socle correspond à **un dossier** (pas à un usager agrégé). Conséquence directe
  de la suppression keyée par numéro de dossier (§2.3) et cohérent avec le mode de lecture
  (0/1/N lignes de l'usager, auto-remplissage si une seule).
- Chaque ligne porte l'**e-mail du titulaire** (`dossier.user.email`), **forcé en minuscules**,
  dans une colonne « propriétaire ». C'est la clé d'identité du DLNUF côté lecture : la seule
  ancre non-usurpable est le compte (mail), jamais une donnée déclarée (DN, N° Tahiti, SIRET).
- La canonicalisation est garantie par construction : c'est la synchro (robot) qui écrit le
  mail normalisé ; la clé est donc la même chaîne à l'écriture et à la lecture.

### 2.2 Mapping : configuration YAML séparée, clé par `stable_id`

- Un bloc **`mapping: { ColonneCanonique: stable_id }`** est ajouté à la configuration
  `baserow_sync` de chaque démarche.
- L'extraction est **keyée par `stable_id`** (identifiant stable, survit au renommage du champ),
  et non plus par libellé. Repli sur le comportement actuel par libellé pour les tables
  **dédiées** (non-socle), qui restent en « convention over configuration ».
- **Le mapping écriture n'est pas unifiable avec le prefill de lecture.** Le préremplissage de
  Mes-Démarches est un mécanisme **interne à la plateforme, ni interrogeable ni remplaçable**
  depuis le robot. Les deux correspondances coexistent donc nécessairement, chacune de son côté.

### 2.3 Suppression : hook générique, flux incrémental, curseur unique

- Le mécanisme per-dossier existant (`task.process(demarche, dossier)` appelé pour chaque
  dossier modifié, `app/lib/verification_service.rb:378`) est **généralisé aux suppressions** :
  ```ruby
  # InspectorTask — nouveau hook, no-op par défaut (symétrique de #process)
  def deleted(demarche, number); end
  ```
  Tout plugin qui veut réagir à une suppression **surcharge `deleted`**. C'est une **capacité
  du framework**, pas un branchement propre à Baserow.
- **Même passe, même curseur.** `VerificationService#check_demarche` calcule
  `since = demarche.checked_at` (`verification_service.rb:157`). Après la boucle des dossiers
  modifiés, une boucle jumelle `DossierActions.on_deleted_dossiers(demarche.id, since)` itère
  la connexion **`deletedDossiers(deletedSince: since)`** et appelle `task.deleted(demarche,
  number)` sur chaque tâche. Un **seul curseur** (`checked_at`) pilote les deux connexions.
- **Rattrapage (cas rare).** Rejouer les suppressions manquées = **remettre `checked_at` en
  arrière** (le mécanisme `reset?` force déjà `EPOCH`). Un seul levier, pas deux à synchroniser.
- **Parité Baserow / Grist obligatoire.** `BaserowSync#deleted` **et** `GristSync#deleted`
  suppriment la ligne où `Dossier == number` dans leur table respective. La parité est déjà la
  règle (vidage de cellules) ; le hook générique la rend gratuite.

### 2.4 Sûreté / RGPD par construction

- Suppression **idempotente** : ligne absente = succès silencieux.
- La suppression ne dépend d'aucune donnée client : elle est pilotée par le flux serveur
  `deletedDossiers`.
- Côté lecture, la valeur source (mail titulaire) est **résolue côté serveur** depuis la
  session / le dossier persisté, jamais lue depuis le client ; **fail-closed** si la
  configuration du référentiel est invalide (jamais de repli en catalogue ouvert).

---

## 3. Lots et charges

Le devis est **global** : chaque ligne est facturée pour elle-même.

| Lot | Contenu | Charge |
|---|---|---|
| **P0 — Mise en place du socle** | Figer le jeu de **colonnes canoniques** (strate A pérenne + B-générique de la grille de fusion) ; **cartographie `stable_id → colonne canonique`** par démarche (harvest MCP `lire_demarche` sur les démarches porteuses) qui alimente le `mapping:` YAML ; **création de la table socle Baserow** via le schema-builder existant (colonnes texte, select, fichier, colonne « propriétaire » e-mail). | **~1,5–2 j** |
| **W1 — Mapping dans la synchro** | Bloc `mapping: { ColonneCanonique: stable_id }` dans la config `baserow_sync` ; extraction **keyée `stable_id`** (repli libellé pour tables dédiées) ; écriture de l'**e-mail titulaire minusculé** dans la colonne propriétaire ; **pièces de la strate A** (statuts, RIB…) mappées en colonnes fichier (dédup nom+taille déjà gérée) ; tests unitaires (résolution mapping, keying, minusculisation) + test système. | **~3 j** |
| **W2 — Propagation de suppression** | Hook générique **`InspectorTask#deleted(demarche, number)`** ; boucle jumelle dans `VerificationService` sur **même curseur `checked_at`** ; requête **`deletedDossiers(deletedSince:)`** + `DossierActions.on_deleted_dossiers` ; implémentations **`BaserowSync#deleted` ET `GristSync#deleted`** (parité) ; tests unitaires + système. | **~2–2,5 j** |
| **L0 — Socle technique de lecture** | Infra du champ `referentiel_de_polynesie` : transmission `champ_id` à l'endpoint `#search` ; autorisation 403 (le dossier doit appartenir au user) ; résolution serveur ; **fail-closed** générique ; lecture de la config méta (colonne « propriétaire »). Prérequis commun de B et C. | **~2 j** |
| **B — Dites-le-nous une fois** | Détection du mode via la colonne « propriétaire » (table méta) + **fail-closed si id mort** + diagnostic ; scope titulaire `dossier.user.email` ; endpoint acceptant un **`q` vide** quand scopé ; ergonomie **liste des 0/1/N lignes de l'usager + auto-remplissage si une seule** au focus ; messages n'échoant jamais le mail ; tests. | **~2,5–3 j** |
| **C — Préremplissage des pièces jointes** | Branche PJ dans `update_prefillable_champ` ; **job asynchrone** download + attach + **re-scan antivirus** (pas de `SAFE` forcé) + **purge idempotente** (seulement si champ `prefilled?`) + échec gracieux ; UI d'attente via refresh Turbo ; éditeur de mapping (cible PJ + validation colonne fichier) ; tests unitaires + système. | **~4–5 j** |

**Sous-total construction : ~15–17,5 j.**

### 3.1 Déploiement

| Lot | Contenu | Charge |
|---|---|---|
| **D1 — Recopie initiale (reprise de l'existant)** | Alimentation du socle avec les dossiers **déjà déposés** (indispensable pour que le DLNUF propose des données dès l'ouverture) : reprise par démarche via remise du curseur `demarche.checked_at` à `EPOCH` (`app/lib/verification_service.rb:157`, mécanisme `reset?` existant), **contrôle qualité du mapping sur données réelles** (champs combinés, PJ conditionnelles N→1), correctifs de cartographie induits. | **~1,5–2 j** |
| **D2 — Accompagnement des services** | Un jour par service : cadrage du `mapping:` de la démarche, recette du prefill sur un dossier réel, points de vigilance (consentement, libellés), transfert. **6 services** (DIREN, Sport/DJS, Jeunesse, Santé, DSFE, Papeete). | **~6 j** (1 j × 6) |

**Total devis : ~22,5–25,5 j.**

---

## 4. Périmètre et hors périmètre

**Dans le périmètre :** P0, W1, W2 (construction écriture) ; L0, B, C (construction lecture) ;
D1, D2 (déploiement : recopie initiale + accompagnement des services).

**Hors périmètre :**
- **Gouvernance RGPD inter-services** : base légale du partage, rétention, habilitations,
  consentement DLNUF. Décision de gouvernance, pas de code — mais l'invariant « durée de vie
  Baserow = durée de vie MD » est désormais **tenu techniquement par W2**, ce qui simplifie
  d'autant le dossier RGPD.
- **Affichage** d'une PJ issue du référentiel (une colonne fichier est cible de prefill, jamais
  exposée comme colonne consultable : pour un fichier, l'immuabilité légale impose la copie des
  octets — c'est déjà le prefill ; un lien live serait mutable).
- **Cascade / filtrage contextuel** par un autre champ du dossier (besoin « Semences »,
  indépendant des subventions).
- **Fiche association partagée + validation mutualisée par visa** : écartée à l'atelier du
  2026-06-22 (friction + responsabilité juridique). On garde la seule commodité de saisie.

---

## 5. Invariants de sécurité et RGPD (transversaux)

1. Clé DLNUF = **e-mail du titulaire** (`dossier.user.email`, minuscule) ; DN / N° Tahiti / SIRET
   exclus comme clé (déclarés, usurpables).
2. Valeur source **jamais** lue depuis le client — résolution serveur (session / dossier).
3. Lecture **fail-closed** si la configuration référentiel est invalide — jamais de repli
   catalogue ouvert.
4. Suppression **idempotente** et pilotée par le flux serveur `deletedDossiers`.
5. **Parité Baserow / Grist** sur la suppression comme sur l'écriture.
6. Prefill PJ : **re-scan antivirus** systématique (pas de `SAFE` forcé).

---

## 6. Hypothèses et risques résiduels

- **Complétude de `deletedDossiers` (risque central).** Le flux incrémental doit remonter
  **toutes** les causes de disparition, **y compris l'expiration de rétention**
  (`reason: expired`). Si ce n'est pas le cas, des lignes survivraient → trou RGPD. Deux
  mitigations : (a) rejouer en reculant `checked_at` (prévu, cas rare) ; (b) à défaut, basculer
  vers un balayage complet périodique (écarté aujourd'hui). **À confirmer sur l'instance MD.**
- **Disponibilité de la connexion `deletedDossiers(deletedSince:)`** sur l'API de l'instance :
  non utilisée aujourd'hui dans le code, à valider (comme le fait le harvest MCP).
- **Qualité de la cartographie P0** : la valeur du DLNUF dépend de la justesse du mapping
  `stable_id → colonne`. Les `stable_id` étant stables au renommage, le risque porte surtout sur
  les champs combinés (« NOM et Prénom ») et les pièces conditionnelles (N→1).
- **Cache de la config méta** (colonne « propriétaire ») : invalider au changement, sinon courte
  fenêtre de scope obsolète.
- **Changement de mail du titulaire** : les dossiers suivent le `user` ; seul Baserow décroche
  jusqu'à resynchronisation (rare, hors code).

---

## 7. Fichiers principaux concernés (indicatif)

**Écriture (robot — ce dépôt) :**
- `app/lib/inspector_task.rb` — hook `deleted(demarche, number)`.
- `app/lib/verification_service.rb` — boucle jumelle suppression (même curseur `checked_at`).
- `app/lib/dossier_actions.rb` — `on_deleted_dossiers`.
- `app/lib/mes_demarches.rb` — requête `DeletedDossiers` (jumelle de `DossiersModifies`).
- `app/lib/baserow_sync.rb` — `#deleted` + câblage mapping.
- `app/lib/grist_sync.rb` — `#deleted` (parité).
- `app/lib/mes_demarches_to_baserow/data_extractor.rb` — extraction keyée `stable_id` + mapping.
- `app/lib/mes_demarches_to_baserow/sync_coordinator.rb` — lecture config `mapping:` + e-mail
  propriétaire minusculé.
- Config YAML de chaque démarche — bloc `mapping:`.
- Table socle Baserow — via le schema-builder existant.

**Lecture (application mes-demarches — dépôt séparé) :**
- `app/models/champs/referentiel_de_polynesie_champ.rb` / `referentiel_champ.rb`.
- `app/controllers/data_sources/referentiel_de_polynesie_controller.rb`.
- `app/lib/referentiel_de_polynesie/baserow_api.rb`.
- `app/components/editable_champ/referentiel_de_polynesie_component*`.
- Job `PrefillPieceJustificativeJob` (nouveau).
