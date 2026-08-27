# Référentiel des navires alimenté par les dossiers acceptés (DBS / laissez-passer 2439)

- **Date** : 2026-08-27
- **Service** : Direction de la biosécurité (DBS)
- **Démarche** : 2439 « Laissez-passer » (production ; clone de test 2792)
- **Objet** : permettre à l'usager de choisir le navire dans une liste **vivante**, alimentée automatiquement
  par les dossiers acceptés, sans doublons d'orthographe et sans publication de révision à chaque ajout.

---

## 1. Décision de périmètre

Le besoin initial visait trois entités : importateurs, exportateurs, navires. Seuls les **navires** sont
retenus dans ce lot.

| Entité | Décision | Motif |
|---|---|---|
| Importateur (destinataire) | **écarté** | Seul le n° TAHITI est saisi ; mes-demarches ramène déjà raison sociale et adresse du registre. Un référentiel n'apporterait qu'une recherche par nom — trop peu pour une table à maintenir. |
| Exportateur (expéditeur) | **écarté** | Un référentiel de Polynésie est **partagé par tous les usagers** de la démarche : chaque transitaire verrait les fournisseurs des autres. Le bon outil est la fonction « Dites-le-nous une fois » (carnet scopé à l'usager) en cours côté mes-demarches, qui lèvera aussi l'exclusion des personnes physiques. |
| Navire | **retenu** | Nom public, aucun pré-remplissage, liste de 499 options aujourd'hui maintenue à la main dans le formulaire ; l'acceptation par l'agent sert de filtre qualité aux noms saisis en « Autre ». |

La brique robot est néanmoins **générique** (entité, clé, colonnes déclarées en YAML) : elle servira telle
quelle à toute entité future dont la visibilité partagée ne pose pas problème.

## 2. Principe

```
usager                  mes-demarches                         Baserow                    robot
  │ tape "warra"  ──▶  champ référentiel (autocomplete)  ──▶  table Navires : contains "warra"
  │ choisit ANL WARRAGUL     ou « Autre » + texte libre
  │ dépose
  │                     agent instruit, accepte
  │                                                                           ◀── dossier accepté
  │                                                            Clé = "anl-warragul" existe ?
  │                                                              non → créer (Nom, Clé, Premier dossier, suivi)
  │                                                              oui → maj colonnes de suivi si plus récent
```

Trois responsabilités, trois lieux :

1. **mes-demarches** offre la recherche, l'option « Autre » et stocke le libellé choisi — sans code, par
   configuration d'un champ `referentiel_de_polynesie`.
2. **Baserow** porte la table, consultable et corrigible par les agents.
3. **le robot** inscrit les nouveaux navires et tient les métadonnées d'usage, sur les dossiers `accepte`.

## 3. Côté démarche 2439

### 3.1 État actuel

- `56854` **Nom du transport maritime** : `drop_down_list` de **499 options**, obligatoire, conditionné par
  `79648 Type de transport = Maritime`.
- Deux formules le lisent : `182314` *Tri-Date-Navire* et `183060` *Tri*.
- Il est lu par les publipostages par **libellé** (`Nom du transport maritime` dans `dbs_lp_champs`, et
  `Dossier.Nom du transport maritime` depuis la démarche 1995 des PV via `dossier_link`).

### 3.2 Cible

Le type d'un champ existant ne peut pas être changé : on **crée un nouveau champ** et on supprime l'ancien.

| Étape | Détail |
|---|---|
| 1. Créer | `referentiel_de_polynesie`, libellé provisoire « Navire », `table_id` = id du nouveau référentiel (§4.3), `mode: autocomplete`, **`drop_down_other: true`**, `hint` : « Tapez au moins 2 lettres du nom du navire ; choisissez “Autre” s'il n'apparaît pas », obligatoire, inséré après `79648`. |
| 2. Condition | Même condition que l'ancien : `Type de transport = Maritime`. |
| 3. Formules | Réécrire `182314` et `183060` en remplaçant `{Nom du transport maritime}` par `{Navire}` (les formules stockent le stable_id : elles ne suivront pas seules). Le service de formules connaît le type `referentiel_de_polynesie` (`formula_expression_service.rb:82`). |
| 4. Supprimer | l'ancien `56854`. |
| 5. Renommer | le nouveau champ en **« Nom du transport maritime »** — les publipostages et la 1995 repartent sans changement de YAML ni de modèle. |
| 6. Publier | Les dossiers des révisions antérieures gardent l'ancien champ ; l'aiguillage par `demarche.revision.date_publication` déjà présent dans `dbs-laissez-passer` couvre la transition. |

Aucun mapping de pré-remplissage : le référentiel ne remplit rien d'autre.

### 3.3 Ce que le robot lira

Pour un `ReferentielDePolynesieChamp`, le robot lit `stringValue` (libellé choisi, ou texte libre si
« Autre ») via le repli de `FieldChecker#graphql_champ_value`. Aucune modification du fragment GraphQL.

## 4. Côté Baserow

### 4.1 Table « DBS - Navires »

| Colonne | Type | Propriétaire | Écrite par le robot |
|---|---|---|---|
| **Nom** | texte, **primaire**, champ de recherche du référentiel | agents (corrections libres) | à la création seulement |
| **Clé** | texte | robot | à la création seulement |
| **Premier dossier** | nombre entier | robot | à la création seulement |
| **Dernier dossier** | nombre entier | robot | à chaque dossier accepté plus récent |
| **Dernière arrivée** | date | robot | à chaque dossier accepté plus récent |

Règle de propriété : le robot **n'écrase jamais** une colonne qu'un humain peut avoir modifiée (Nom) ;
il tient seul les colonnes de suivi, que personne ne saisit à la main. C'est ce qui résout la contradiction
apparente entre « ne pas toucher aux lignes existantes » et « métadonnées à jour ».

La **Clé** garde l'orthographe telle que les usagers la tapent (normalisée) : si un agent embellit le Nom,
la Clé continue de rattraper les saisies suivantes. « Dernière arrivée » plutôt que la date de dépôt : c'est
la visite réelle du navire, et c'est ce qui répond à « ce navire ne vient plus ».

Écarté : un compteur « Nombre de passages » (lecture-incrément non idempotent : un retraitement le fausse)
et l'usage du `updated_on` Baserow comme « dernière utilisation » (confond usage par un dossier et retouche
par un agent ; repose sur un effet de bord de PATCH à vide que notre `RowUpserter` évite volontairement).

### 4.2 Jetons

- **Lecture** pour mes-demarches : jeton porté par la ligne de configuration du référentiel (§4.3).
- **Écriture** pour le robot : configuration nommée `DBS` de la table `BASEROW_TOKEN_TABLE` (ou jeton par
  défaut), comme pour `baserow_sync`.

### 4.3 Déclaration du référentiel

Une ligne dans la table de configuration des référentiels de Polynésie (`API_BASEROW_CONFIG_TABLE` côté
mes-demarches) : `Nom` = « DBS - Navires », `Actif` coché, `Table` = id de la table, `Token` = jeton
lecture, `Champ de recherche` = id de la colonne **Nom**. Vérification : `lister_referentiels_de_polynesie`
doit la renvoyer.

### 4.4 Amorçage

Script ponctuel (`bin/` ou tâche rake, non versionné en production) :

1. lire les 499 `drop_down_options` de `56854` (via `lire_demarche` ou GraphQL) ;
2. pour chacune : `Nom` = option telle quelle, `Clé` = normalisation (§5.3), colonnes de suivi vides ;
3. **dédoublonner sur Clé** et produire la liste des collisions (la liste actuelle en contient probablement :
   doubles espaces, casse) pour que la DBS tranche avant l'ouverture ;
4. ne rien faire sur l'historique des dossiers : la liste était fermée, il n'y a rien à découvrir.

## 5. Côté robot : tâche `referentiel_upsert`

### 5.1 Place dans le framework

`ReferentielUpsert < FieldChecker`, clé YAML `referentiel_upsert`, utilisée en **`when_ok`** (comme
`baserow_sync`) ; le filtre d'état passe par `must_check?` avec `etat_du_dossier: [accepte]` **explicite**
(le défaut de `FieldChecker` est `['en_construction']`). `version` hérite du hachage des paramètres : tout
changement de configuration retraite les dossiers.

### 5.2 Configuration

```yaml
- referentiel_upsert:
    etat_du_dossier: [ accepte ]
    baserow:
      table_id: 1234          # requis
      token_config: 'DBS'     # optionnel
    cle: "{Nom du transport maritime}"   # requis — template FieldChecker, puis normalisation
    colonne_cle: Clé                     # défaut : Clé
    creation:                            # écrites à la création seulement
      - colonne: Nom
        champ: Nom du transport maritime
      - colonne: Premier dossier
        champ: number
    suivi:                               # écrites à la création ET mises à jour
      - colonne: Dernier dossier
        champ: number
      - colonne: Dernière arrivée
        champ: Date d'arrivée
    horodatage: Dernière arrivée         # optionnel — colonne de `suivi` qui gouverne la mise à jour
```

- `creation` / `suivi` reprennent la syntaxe `colonne:` / `champ:` des publipostages ; une chaîne seule
  vaut pour les deux noms. `champ` accepte les chemins habituels de `FieldChecker` (`number`,
  `date_depot`, `Dossier.xxx`…).
- `required_fields` : `baserow`, `cle`. `authorized_fields` : `colonne_cle`, `creation`, `suivi`,
  `horodatage`. Validation à l'initialisation (pattern `@errors`) : `baserow.table_id` présent,
  `horodatage` (s'il est donné) désigne une colonne de `suivi`.

### 5.3 Normalisation de la clé

`instanciate(cle)` puis **`String#parameterize`** (translittération des accents, minuscules, tout
caractère non alphanumérique remplacé par un tiret, tirets compressés). Exemples :
« ANL  Warragul » → `anl-warragul` ; « Île de Ré » → `ile-de-re`. Même primitive que
`field_value_check.rb:33`. Clé vide (champ masqué : transport aérien) → la tâche **ne fait rien**, sans
avertissement.

### 5.4 Algorithme

```
cle = normaliser(instanciate(params.cle))         ; return si vide
rows = table.find_by_normalized(colonne_cle, cle)
si rows vide :
    créer { colonne_cle => cle } ∪ valeurs(creation) ∪ valeurs(suivi)
sinon :
    row = rows.first  (plusieurs → warning journalisé, on prend la première)
    si horodatage configuré et row[horodatage] présent et valeur_dossier(horodatage) <= row[horodatage] :
        return                                     ; dossier plus ancien ou égal : rien à faire
    patch = valeurs(suivi) qui diffèrent de row     ; PATCH à vide interdit (historique Baserow)
    update_row(row.id, patch) si patch non vide
```

`valeurs(...)` formate selon le type de la colonne Baserow (métadonnées `table.fields`) : `date` →
`AAAA-MM-JJ`, `number` → entier/décimal, sinon `to_s`. Une valeur de dossier vide n'écrase jamais une
colonne de suivi (on garde la dernière information connue).

**Idempotence** : la règle « seulement si plus récent » rend un retraitement (version bump, réouverture
d'un vieux dossier) sans effet sur les métadonnées ; la création n'a lieu qu'en absence de clé.

### 5.5 Erreurs

Baserow injoignable ou réponse en erreur : l'exception remonte comme pour toute tâche — `apply_task`
marque le `check` en échec et rapporte (`report_error`). Pas d'option `continuer_si_erreur` : une
inscription manquée doit se voir.

### 5.6 Fichiers

- `app/lib/referentiel_upsert.rb` — la tâche (configuration, orchestration).
- `app/lib/referentiel_upsert/` si le formatage par type mérite d'être isolé (`value_formatter.rb`) ; sinon
  tout tient dans la tâche (~150 lignes).
- `spec/lib/referentiel_upsert_spec.rb`.
- `docs/CONFIGURATION_GUIDE.md` : entrée dans la liste des FieldCheckers + pattern « référentiel vivant ».

### 5.7 Configuration de la 2439

Ajout en `when_ok` du bloc `dbs-laissez-passer` **existant** (un seul point d'entrée par démarche :
`checked_at` est partagé), dans la branche `par défaut` et la révision courante :

```yaml
- referentiel_upsert: *dbs_navires_upsert
```

avec l'ancre définie une fois dans le fichier. Fichier : `dbs_laissez-passer.yml` (staging d'abord, via
`deployment/`).

## 6. Tests

Unitaires (`Baserow::Table` doublé) :

1. clé vide → aucun appel Baserow ;
2. clé absente → `create_row` avec Clé + création + suivi, formats date/nombre respectés ;
3. clé présente, dossier plus récent → `update_row` avec les seules colonnes de suivi qui changent ;
4. clé présente, dossier plus ancien ou égal → aucun appel ;
5. clé présente, sans `horodatage` → mise à jour systématique du suivi ;
6. plusieurs lignes pour une clé → première prise, warning ;
7. normalisation : accents, casse, espaces multiples, ponctuation ;
8. validation de configuration : `table_id` manquant, `horodatage` hors `suivi`.

Live (staging, clone 2792) : un dossier avec navire existant, un avec « Autre » nouveau, un avec « Autre »
variante d'orthographe d'un existant, un aérien ; vérifier la table, puis les publipostages LP et le PV 1995
qui lisent le champ par libellé.

## 7. Ordre de mise en œuvre

1. Table Baserow + jetons + ligne de configuration du référentiel ; amorçage des 499 (rapport de collisions
   à la DBS).
2. Tâche robot + tests ; déploiement staging.
3. Démarche 2792 (clone) : nouveau champ, condition, formules, suppression, renommage ; tests live.
4. Reproduire sur la 2439 ; YAML production.

## 8. Points à vérifier en live

- Le repli `string_value` renvoie bien le texte libre quand l'usager choisit « Autre ».
- Les deux formules réécrites évaluent correctement un champ référentiel (valeur principale).
- Le `contains` Baserow est insensible à la casse mais **pas aux accents** : sans incidence pour des noms de
  navires (majuscules ASCII), à garder en tête si la brique est réutilisée.

## 9. Hors périmètre (phase 2, si la DBS le demande)

- **Alias** : colonne de clés supplémentaires consultée après `Clé`, pour qu'un agent puisse fusionner deux
  lignes sans que la suivante recrée la mauvaise.
- **Préfixes à ignorer** (`MV`, `M/V`, `MS`) dans la normalisation.
- Importateurs et exportateurs, à reprendre quand « Dites-le-nous une fois » sera disponible côté
  mes-demarches.
- « Nom du transport aérien » (18 vols, liste stable) : inchangé.

## 10. Charge estimée

| Poste | Estimation |
|---|---|
| Tâche robot + tests unitaires + doc | 0,5 – 1 j |
| Baserow (table, jetons, config référentiel) + amorçage et rapport de collisions | 0,5 j |
| Démarche (clone puis production) + tests live + YAML | 0,5 j |
| **Total** | **≈ 1,5 – 2 j** |
