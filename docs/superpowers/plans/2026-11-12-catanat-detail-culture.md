# CATANAT 3335 — Détail culture (bio, m²) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** dans la 3335, recueillir pour chaque culture la surface et le statut bio, et les reporter dans l'annotation « Cultures par famille » sous la forme « tomate (75 m² non bio), poivron (100 m² bio) ».

**Architecture :** le formulaire (brouillon 3335, via les outils de mcp-mes-demarches) reçoit une question Oui/Non « Culture en partie bio » et un bloc répétable « Détail culture » dont la question bio dépend de cette réponse. Le plugin `CulturesParFamille` de l'inspecteur lit ce bloc en priorité, sinon l'ancienne liste multiple « Cultures sur ces parcelles », et regroupe par famille comme aujourd'hui.

**Tech Stack :** Ruby/Rails (inspecteur, RSpec), API GraphQL mes-demarches via `src/tools.ts` de mcp-mes-demarches (script `run.mts` du scratchpad).

**Spec (design validé en conversation le 2026-11-12) :**
- Bloc répétable « Détail culture », affiché si « Surface cultivée » > 0, avec : « Culture » (choix simple, libellés de `CATANAT/Culture liste.csv`), « Surface (m²) » (entier positif), « Bio / non bio » (choix simple « Bio » / « Non bio »). Les trois obligatoires.
- « Bio / non bio » affiché seulement si le demandeur répond Oui à « Culture en partie bio » (Oui/Non, obligatoire, affiché si « Surface cultivée en bio » > 0). Une formule était prévue mais mes-demarches ne permet pas encore référentiels importés et formules dans un même formulaire (bug à corriger).
- Statut écrit par le robot : surface bio vide ou 0 → « non bio » ; surface bio ≥ surface cultivée → « bio » ; sinon réponse du demandeur.
- Repli : « Détail culture » non vide → on l'utilise ; sinon « Cultures sur ces parcelles » non vide → comportement actuel ; sinon pas de culture.
- « Cultures sur ces parcelles » reste visible pour tous, non obligatoire, libellé « (ancien champ, ne plus remplir) ». Son sort sera décidé plus tard.
- Pas de changement sur la 3893 (elle ne recopie « Cultures » que comme texte).

## Global Constraints

- Libellés, messages, commentaires en français.
- 3335 : on ne modifie que le brouillon ; l'utilisateur republie lui-même.
- Format d'une culture : `<culture> (<N> m² <bio|non bio>)` ; sans statut connu : `<culture> (<N> m²)` ; sans surface : `<culture>`. Séparateur `, `.
- Pas de commit/push sans demande de l'utilisateur (branche locale `catanat-detail-culture` depuis `dev`).

## Review Focus

- Deux lignes de la même culture (une bio, une non bio) : les deux apparaissent, pas de dédoublonnage côté détail.
- Ligne de bloc sans culture (ligne vide ajoutée par erreur) : ignorée.
- « Surface cultivée en bio » > « Surface cultivée » (saisie incohérente) : statut « bio », pas d'erreur.
- Dossier ancien en partie bio sans réponse « Bio / non bio » : statut omis, `tomate (75 m²)`.
- Culture absente de la table des familles : famille « Autres » + warning, comme aujourd'hui.

---

### Task 1 : Formulaire 3335 (brouillon)

**Fichiers :** aucun dans un dépôt ; opérations JSON passées à `run.mts` (scratchpad), lecture finale de la démarche pour contrôle.

- [ ] **Step 1 : question bio.** `supprimer_champ` 201956 (formule d'essai). `ajouter_champ` yes_no « Culture en partie bio », obligatoire, après 201135, description « Répondez Oui si une partie seulement de votre surface cultivée est en bio. » ; condition « Surface cultivée en bio » (201135) > 0.
- [ ] **Step 2 : options.** Lire le CSV (latin1, `;`), colonne 1, `strip`, sans vide ni doublon, ordre du fichier → `drop_down_options`.
- [ ] **Step 3 : bloc.** `ajouter_champ` repetition « Détail culture », obligatoire, après 200354, description « Une ligne par culture : la culture, sa surface en m² et, si une partie seulement de l'exploitation est en bio, si cette culture est bio. » ; condition « Surface cultivée » > 0. Enfants : drop_down_list « Culture » (options du step 2, obligatoire), integer_number « Surface (m²) » (positive_number, obligatoire), drop_down_list « Bio / non bio » (`["Bio","Non bio"]`, obligatoire) avec condition « Culture en partie bio » egal true.
- [ ] **Step 4 : ancien champ.** `modifier_champ` 200354 → obligatoire false, libellé « Cultures sur ces parcelles (ancien champ, ne plus remplir) », description « Remplacé par le bloc « Détail culture » ci-dessous. ».
- [ ] **Step 5 : contrôle.** `lire_demarche` 3335 : 201956 supprimé, « Culture en partie bio », bloc et 3 enfants présents, conditions comme ci-dessus. Si la condition d'un enfant sur un champ hors bloc est refusée, s'arrêter et le signaler.

⚠️ Le libellé de 200354 change : la config de l'inspecteur doit suivre (Task 2, step 5).

### Task 2 : `CulturesParFamille` lit « Détail culture »

**Fichiers :**
- Modify : `app/lib/cultures_par_famille.rb`
- Modify : `spec/lib/cultures_par_famille_spec.rb`
- Modify : `storage/configurations/dag_catanat_inscription.yml` (bloc `cultures_par_famille`)

**Interfaces :**
- Nouveaux paramètres facultatifs (`authorized_fields`) : `bloc_detail` (aucun détail lu si absent), `champ_culture` (défaut « Culture »), `champ_surface` (« Surface (m²) »), `champ_bio` (« Bio / non bio »), `champ_surface_cultivee` (« Surface cultivée »), `champ_surface_bio` (« Surface cultivée en bio »).
- `version` → `super + 2`.
- `regroupe(cultures)` prend désormais des paires `[culture, texte]` (texte = libellé formaté) : groupement par famille sur `culture`, jointure des `texte`. Dédoublonnage (`uniq`) uniquement pour l'ancienne liste.

- [ ] **Step 1 : tests (rouges)** dans `spec/lib/cultures_par_famille_spec.rb`, contexte `with Détail culture` : le dossier a en plus un `RepetitionChamp` « Détail culture » (rows de champs `Culture` DropDownListChamp `string_value`, `Surface (m²)` IntegerNumberChamp `int_value`, `Bio / non bio` DropDownListChamp) et les IntegerNumberChamp « Surface cultivée » / « Surface cultivée en bio » ; le contrôle reçoit `bloc_detail: 'Détail culture'`.
  - `uses the detail block in priority` : lignes tomate 75 « Non bio », vanille 100 « Bio », surfaces 500/100 → ligne Vanille `vanille (100 m² bio)`, ligne maraîchères `tomate (75 m² non bio)` ; l'ancienne liste (non vide) est ignorée.
  - `writes non bio when no surface is in bio` : surface bio nil puis 0, pas de réponse → `tomate (75 m² non bio)`.
  - `writes bio when the whole surface is in bio` : 500/500 et 500/600, réponse « Non bio » → `tomate (75 m² bio)`.
  - `keeps both rows of a crop grown bio and non bio` : tomate 75 Bio + tomate 50 Non bio → `tomate (75 m² bio), tomate (50 m² non bio)`.
  - `omits what is missing` : partiel 500/100 sans réponse → `tomate (75 m²)` ; surface nil → `tomate` ; ligne sans culture ignorée.
  - `falls back to the old list when the detail block is empty` : bloc sans lignes → résultat identique au test existant `writes one row per family…`.
  - Les tests existants restent verts sans `bloc_detail`.
- [ ] **Step 2 :** `bundle exec rspec spec/lib/cultures_par_famille_spec.rb` → FAIL sur les nouveaux tests.
- [ ] **Step 3 : implémenter.** `cultures` → `detail.presence || ancienne_liste` ; `detail` parcourt `object_field_values(@dossier, @params[:bloc_detail], log_empty: false).flat_map { Array(it.rows) }`, lit chaque enfant par libellé via `select_champ(row.champs, …)` et `champ_value`. `statut(reponse)` applique la règle de la spec (surfaces lues avec `object_field_values` + `int_value`).
- [ ] **Step 4 :** même commande → PASS ; `bundle exec rubocop app/lib/cultures_par_famille.rb spec/lib/cultures_par_famille_spec.rb` → aucune offense.
- [ ] **Step 5 : config.** Dans `dag_catanat_inscription.yml` : `champ: "Cultures sur ces parcelles (ancien champ, ne plus remplir)"`, `bloc_detail: "Détail culture"` ; mettre à jour le commentaire au-dessus. Ajouter aux `familles` les cultures du CSV absentes de la table (colonne Famille vide → aucune, elles restent « Autres »). Vérifier : `bin/rails runner 'YAML.load_file("storage/configurations/dag_catanat_inscription.yml", aliases: true)'`.
- [ ] **Step 6 : commit local** sur `catanat-detail-culture` (`git add` des 3 fichiers + ce plan).

### Task 3 : vérification de bout en bout (après republication par l'utilisateur)

- [ ] Créer/compléter un dossier de test 3335 avec « Détail culture » (un cas partiel bio), lancer `bin/rake "dossiers:check[<n°>]"`, relire « Cultures par famille » : format attendu.
- [ ] Relancer un dossier ancien (sans détail) : « Cultures » inchangé.
- [ ] Documenter les nouveaux paramètres dans `docs/CONFIGURATION_GUIDE.md` (section `cultures_par_famille`).
