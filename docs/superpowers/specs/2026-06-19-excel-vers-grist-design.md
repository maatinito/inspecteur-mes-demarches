# Spec — Synchronisation d'un Excel joint vers une table liée Grist (`excel_vers_grist`)

Date : 2026-06-19
Statut : design validé, prêt pour plan d'implémentation

## 1. Contexte et objectif

Un projet doit synchroniser des dossiers Mes-Démarches vers Grist, mais **aussi**
les lignes d'un **fichier Excel joint** au dossier, qui doivent être « étendues »
(explosées) dans une **table liée au dossier** — exactement le pattern des blocs
répétables, mais avec une source Excel au lieu d'un bloc natif.

Ce traitement est aujourd'hui prototypé dans un **workflow n8n** dont le seul rôle
est le parsing de l'Excel. Or le robot sait déjà : lire un Excel joint (`roo`,
`Excel::GetSheets`), parler à Grist (`Grist::Client`), et upserter des lignes dans
une table liée (`MesDemarchesToGrist`). n8n n'apporte donc **aucune valeur unique**
et ajoute un second runtime à exploiter, monitorer et sécuriser.

**Objectif** : rapatrier ce traitement dans le robot sous forme d'un plugin dédié,
en réutilisant au maximum l'existant, et en supprimant la dépendance à n8n pour ce flux.

## 2. Périmètre

### Dans le périmètre (chantier B)
- Un plugin `ExcelVersGrist` (FieldChecker) qui, pour un dossier :
  1. lit le fichier Excel d'un champ PieceJustificative,
  2. décide s'il faut (re)traiter via un **checksum de traitement** (cf. §6),
  3. extrait les lignes (réutilise `Excel::GetSheets`),
  4. crée les colonnes cibles manquantes + une colonne checksum technique (§7),
  5. upserte les lignes dans la table liée (réutilise `MesDemarchesToGrist`).
- Extension de `Excel::GetSheets` (extraction) : sélection de feuille par nom **ou**
  position, sanitization des noms de colonnes, exposition des types inférés.
- Mapping colonnes source→cible déclaratif en YAML, avec types optionnels.

### Hors périmètre (YAGNI — décidé explicitement)
- **CSV** : non supporté. xlsx (et formats lus par `roo`) uniquement.
- **Parsing de locale** : inutile. En xlsx les nombres/dates sont stockés comme
  vraies valeurs ; `roo` renvoie déjà `5435.56` (Float) et des `Date`/`DateTime`
  Ruby. On s'appuie sur le typage natif de `roo`.
- **Détection avancée des bornes de tableau** (en-têtes fusionnés multi-niveaux,
  lignes de total, préambules) : la détection `header_line` de `GetSheets` est
  basique mais **éprouvée sur les fichiers réels**. On ne va pas plus loin.
- **Recopie du binaire `.xlsx` dans Grist** : on stocke les lignes, pas le fichier.
  Le « checksum #1 / re-upload » (cf. §6) ne concerne donc pas ce plugin.
- **Synchro des avis vers Grist** : non nécessaire pour ce projet (décision). C'est
  une feature Baserow-only, explicitement gardée côté Grist
  (`SchemaBuilders::AvisBuilder` lève `NotImplementedError` pour `GristTarget`).
  Trou de parité connu, hors périmètre A + B.

## 3. Décision d'architecture

### 3.1 Réutiliser, ne pas réimplémenter
La cible est une table **liée à la table dossier** → c'est le pattern bloc
répétable. On réutilise `MesDemarchesToGrist::RowUpserter` (upsert + diff
ligne-à-ligne) et la logique de colonnes de `RepetableBlockBuilder`, plutôt que de
dupliquer la partie la plus délicate.

### 3.2 Extension `GetSheets` + nouveau plugin de synchro (hybride)
- **Extraction** → étendre `Excel::GetSheets`. Les ajouts (sélection feuille,
  sanitization, types inférés) sont des préoccupations d'extraction, légitimes ici,
  et rétrocompatibles (paramètres optionnels, défaut = comportement actuel).
- **Synchro** → nouveau plugin `ExcelVersGrist`. Raison : `GetSheets` vit dans un
  modèle pipeline (`process_row` → `output`) consommé par `Partition`/`Group` ;
  y injecter la logique Grist le dénaturerait et risquerait une régression. La
  synchro est par ailleurs un FieldChecker « par dossier » (comme `GristSync`),
  modèle d'exécution différent.

### 3.3 Création de schéma autonome au runtime (écart assumé)
Le sync existant ne crée rien (`ensure_schema` est un no-op, skip si table absente :
le provisioning passe par l'UI `admin/schema_builder_controller`). Pour ce plugin
on s'écarte volontairement : un Excel legacy **n'est pas** un bloc natif, donc le
schema-builder ne peut pas dériver ses colonnes des descripteurs — il n'y a pas de
chemin « revu » à court-circuiter. Le plugin est donc **autosuffisant** : il crée
ses colonnes au runtime. Garde-fous remplaçant la revue humaine : type par défaut
`Text`, override de type dans le mapping, et un **rapport** de ce qui est créé.

## 4. Composants

### 4.1 `Excel::GetSheets` (étendu)
Nouveaux paramètres optionnels :
- `feuille` : `Integer` → position (1-based) ; `String` → nom. **Absent → 1ʳᵉ feuille**.
  Rétrocompat : **non bloquant** — vérification faite, `excel/get_sheets` n'est utilisé
  dans **aucune** config déployée (prod ni staging : 0 occurrence, seules
  `excel/partition`/`group`/`from_repetitions` le sont) ni dans aucune classe
  applicative (uniquement `spec/factories/publipostage_v2.rb:48`). On peut donc
  basculer le défaut et refactorer `GetSheets` librement.
- exposition, par feuille, d'un descripteur de colonnes : `{ nom_sanitizé, type_inféré, en_tête_brut }`.

Inchangé : lecture du `.xlsx` du champ PieceJustificative, `header_line`,
`each_row_streaming`, `PieceJustificativeCache`.

### 4.2 `ExcelVersGrist` (FieldChecker, nouveau)
Responsabilités :
- `must_check?` / `etat_du_dossier` (gating standard FieldChecker).
- Gate checksum #2 (§6) : lire la colonne checksum de la main row, comparer aux
  checksums source MD ; si égal → skip total (pas d'extraction ni d'upsert).
- Appel à l'extraction (`GetSheets`), mapping source→cible (§5).
- `ensure_columns` : créer colonnes manquantes (opt-out) + colonne checksum technique.
- Upsert des lignes via `MesDemarchesToGrist::RowUpserter`.
- Écriture du checksum sur la main row en fin de traitement réussi.
- **Collecte des erreurs métier** (fichier non-`.xlsx`, non parsable/corrompu, feuille
  introuvable, en-têtes/colonnes mappées absentes, lignes rejetées…) et, si
  `colonne_erreurs` configurée, écriture du message sur la main row (cf. §9).
- Capture Sentry + `continuer_si_erreur` (aligné sur `GristSync`).

### 4.3 Réutilisations
- `MesDemarchesToGrist::RowUpserter` (diff ligne-à-ligne, upsert).
- Logique de création de colonnes de `RepetableBlockBuilder` / `Grist::Client`.
- `Grist::Config` / `Grist::Client`.

## 5. Configuration YAML

```yaml
sync_excel_dossiers:
  demarches: [XXXX]
  <<: *par_defaut
  etat_du_dossier: [en_instruction, accepte]
  when_ok:
    - excel_vers_grist:
        champ: "Tableau des bénéficiaires"   # champ PieceJustificative (.xlsx)
        grist:
          doc_id: "aBC123xYz"
          table_id: "Beneficiaires"          # table LIÉE au dossier, créée à la main
        feuille: 1                            # nom (String) ou position 1-based (Integer)
        options:
          creer_colonnes_manquantes: true     # défaut true ; false = pas d'auto-création
          continuer_si_erreur: true
          colonne_erreurs: "Erreurs sync"     # optionnel : colonne (main row) où reporter
                                              # les erreurs ; absent → erreurs en logs/Sentry seulement
        # Mapping optionnel. Absent → en-têtes Excel (sanitizés) = noms de colonnes.
        # Source seule → cible = source. Type optionnel.
        colonnes:
          "Nom de famille": "Nom"
          "Montant versé":
            cible: "Montant"
            type: numeric
          "Date d'attribution":
            cible: "Date"
            type: date
```

Le mapping se déploie sans rebuild d'image (fichiers YAML poussés via
`mirror_staging.sh` / `mirror_production.sh`).

## 6. Détection de changement — deux checksums orthogonaux

| | Checksum #1 « upload » | Checksum #2 « traitement lignes » |
|---|---|---|
| Décision | Re-uploader le binaire ? | Re-exploser le fichier en lignes ? |
| Aujourd'hui | approx. par `nom+taille` | **n'existe pas** |
| Concerne | le binaire (recopie attachment) | le contenu parsé → lignes |
| Ce plugin | **hors périmètre** (on ne recopie pas le `.xlsx`) | **nécessaire** |

- Source du signal : le champ `checksum` (MD5 base64) exposé par le type `File` de
  l'API GraphQL Mes-Démarches. **Déjà récupéré** par le fragment `ChampInfo`
  (`app/lib/mes_demarches.rb`, lignes 166 & 173 : `checksum`/`filename`/`byteSize`
  sur `files`). **Aucune modification de requête nécessaire.**
- Ni Grist ni Baserow n'exposent de checksum de contenu (uniquement `nom+taille`) →
  le signal robuste vient **de la source**, pas de la cible.
- **Multi-fichiers** : un PieceJustificative peut porter plusieurs fichiers → la
  colonne stocke l'ensemble des checksums **triés puis concaténés en CSV** (texte,
  séparés par virgule ; tri = comparaison insensible à l'ordre).
- **Stockage : colonne sur la main row** (pas une annotation MD). Raisons : la main
  row est déjà lue à chaque passage (lecture gratuite) ; co-localisation
  données/garde (si la table Grist est vidée, le marqueur disparaît avec → re-sync
  correct, pas de désync).

## 7. Création de schéma & règles d'extraction

### 7.1 Création de colonnes
- **Table des lignes** : créée **manuellement** (mapping bespoke). Le plugin ne la crée pas.
- **Colonnes manquantes** dans cette table : auto-créées par défaut, désactivables
  via `creer_colonnes_manquantes: false`.
- **Colonne checksum** (technique) sur la main row : toujours auto-créée (ensure once
  par démarche/run, via le hook `ensure_schema`).
- **Type figé à la création** : on ne modifie **jamais** le type d'une colonne
  existante. Workflow assumé : traiter un 1ᵉʳ fichier → ajuster les types à la main
  dans Grist → retraiter. Un conflit de type au re-sync est **loggé**, pas appliqué.

### 7.2 Inférence de type (depuis les valeurs typées par `roo`)
Mapper la classe Ruby des valeurs de la colonne → type Grist :
`Float → numeric`, `Integer → int`, `Date → date`, `DateTime → datetime`,
`true/false → bool`, colonne **mixte ou vide → Text** (jamais de perte de donnée).
Override possible par le `type` du mapping.

### 7.3 Sanitization des noms de colonnes
Grist tolère les espaces. On retire ponctuation et retours-ligne, on `trim`, on
collapse les espaces multiples. Gérer : **doublons** (suffixe `_2`, …) et **en-tête
vide mais colonne remplie** (nom généré `Colonne_<index>`).

### 7.4 Résilience inter-dossiers
Matcher les colonnes **par nom d'en-tête sanitizé** (pas par position) → robuste au
réordonnancement. Un renommage d'en-tête casse le rattachement (acceptable, à
documenter). Dérive de schéma (nouvelle colonne dans un dossier ultérieur) :
auto-ajout si `creer_colonnes_manquantes` (défaut), tracé dans le rapport.

## 8. Prérequis / dépendance — durcissement de `GristSync` (chantier A)

`GristSync` n'a **jamais été déployé ni testé en prod** (4 commits, vs 28 pour
Baserow), mais l'analyse de dé-risquage (2026-06-19) montre qu'il est
**fonctionnellement complet et architecturalement sain**, pas un chantier de
construction :

- Pipeline complet (extract→filter→upload→upsert main→sync blocs), découverte de
  tables, upsert bloc par `(Dossier, Ligne)`, suppression des orphelins, réutilisation
  des attachments : **déjà présents**.
- **Le diff ligne-à-ligne EXISTE déjà** (`RowUpserter.filter_changed_fields` :
  Integer/Numeric/ChoiceList/Bool/Attachments/Text/Date). Correction d'une affirmation
  antérieure : rien à porter depuis Baserow.
- Couche de typage **bien testée** (`TypeMapper`, `DataExtractor`, `RowUpserter`).

### Contrat Grist validé en live (MCP grist-server, 2026-06-19)
6 des 7 hypothèses confirmées sur instance réelle : Choice (string), ChoiceList
(`["L",…]`), Date/DateTime (epoch **secondes** → date correcte), Bool, Ref bloc→main
(id entier), structure `{id, fields:{…}}`. Le `DataExtractor`/`RowUpserter` sont
alignés sur la réalité de l'API.

### Reste à faire (chantier A réel, ~1 j avec Claude)
1. Écrire `spec/lib/mes_demarches_to_grist/sync_coordinator_spec.rb` (client stubbé,
   miroir du spec Baserow) → flush des bugs de câblage hors-ligne. ~0,5 j.
2. **Seule inconnue résiduelle** : sémantique de l'upsert natif `PUT /records` avec
   `require:` — match-et-update vs doublon, **surtout le match sur colonne `Ref`**
   pour les lignes de bloc (`require: {Dossier: ref_id, Ligne}`). Non testable via le
   MCP. → valider par un **run staging** sur une démarche bac-à-sable (observer si les
   re-syncs créent des doublons). ~0,5 j.
3. (Option, perf) Router les lignes de bloc via `RowUpserter` pour bénéficier du diff
   (`upsert_block_row` envoie aujourd'hui tous les champs ; l'upsert natif reste
   idempotent côté serveur). ~0,2 j.

Le plan d'implémentation de B déclare A (point 2) comme dépendance.

### Bug de ré-upload des pièces jointes (trouvé + corrigé, 2026-06-21)
`GristFileUploader` écrivait le téléchargement dans un `Tempfile` au nom aléatoire
(`grist_upload-XXXX.xlsx`) ; Grist stockait ce nom comme `fileName`, donc la dé-dup
nom+taille (`DataExtractor#normalize_files`) ne matchait jamais → ré-upload à chaque
synchro. **Corrigé** (commit `9163976`) : écrire le binaire sous le vrai nom visible.
Diagnostic confirmé sur la prod (doc `tYVZeA7kfoWQ`, dossier 404982) : nom stocké =
tempfile, taille = identique.

**Évolution à réévaluer en B (double sécurité, sans colonne)** : ajouter au critère
nom+taille une comparaison de timestamps `File.createdAt (MD) > attachment.timeUploaded
(Grist)` → détecte un remplacement même à nom+taille inchangés. Les deux dates existent
déjà (GraphQL `File.createdAt`, métadonnées Grist `timeUploaded`). Seule réserve :
comparaison inter-horloges MD↔Grist (tolérable vu NTP + sync espacées de ~10 min).

## 9. Gestion d'erreurs
- Champ absent / pas de `.xlsx` : log + skip (pas d'erreur fatale).
- Table cible introuvable : skip silencieux (aligné sur le comportement sync existant).
- Erreur d'upsert : capture Sentry ; `raise` sauf si `continuer_si_erreur: true`.
- Échec partiel : ne **pas** écrire le checksum (sinon on figerait un état incomplet).

### Colonne d'erreurs (optionnelle) — `colonne_erreurs`
Rend les erreurs visibles **dans Grist** (au niveau du dossier) plutôt que noyées dans
les logs/Sentry — utile pour l'instructeur et le débogage de configs sur des Excel legacy.

- **Emplacement** : une colonne Text sur la **main row** (un message par dossier), comme
  la colonne checksum. **Auto-créée** (ensure-once) dès que `colonne_erreurs` est défini,
  indépendamment de `creer_colonnes_manquantes` (c'est une colonne technique requise par
  l'option).
- **Contenu** : messages métier lisibles, concaténés — p.ex. « Le fichier n'est pas un
  .xlsx », « Fichier illisible/corrompu », « Feuille "X" introuvable », « Colonnes
  attendues absentes : A, B », « 3 ligne(s) ignorée(s) (vides) ».
- **Cycle de vie** : écrite en fin de traitement ; **vidée (`''`) en cas de succès** pour
  ne pas laisser une erreur obsolète d'un passage précédent. En cas d'erreur, le checksum
  #2 n'est **pas** écrit → le dossier est re-traité au passage suivant et le message se
  rafraîchit (idempotent).
- **Complémentaire** de Sentry : Sentry capte les exceptions techniques ; cette colonne
  expose les erreurs métier/données attendues, sans interrompre le traitement des autres
  dossiers (cf. `continuer_si_erreur`).

## 10. Tests
- **`GetSheets` étendu** : corpus de **vrais fichiers tordus** (préambule, feuilles
  multiples, en-têtes sales, colonnes vides/doublons, codes à zéro de tête) — c'est
  la pièce à tester en priorité. Note : `GetSheets` n'étant **pas exercé en prod**
  (cf. §4.1), ce corpus est la **validation principale**, pas un filet anti-régression.
- Inférence de type : cas Float/Int/Date/DateTime/Bool/mixte/vide.
- Sanitization : doublons, en-têtes vides, ponctuation, retours-ligne.
- Gate checksum : inchangé → skip ; modifié → retraitement ; multi-fichiers (ordre).
- `ensure_columns` : création, opt-out, type figé sur colonne existante.
- Upsert : création, mise à jour partielle, idempotence (re-run sans changement).
- Colonne d'erreurs : message écrit en cas d'erreur (non-xlsx, illisible, colonnes
  absentes) ; **vidée en cas de succès** ; auto-création quand `colonne_erreurs` est défini.

## 11. Décisions tranchées
1. **Défaut feuille = 1ʳᵉ feuille** (usage réel des projets). Caveat rétrocompat en §4.1.
2. **Aucune modif de requête** : `checksum` déjà présent dans le fragment `ChampInfo`
   (`app/lib/mes_demarches.rb:166,173`).
3. **Colonne checksum = texte CSV** (checksums triés, concaténés par virgule).
