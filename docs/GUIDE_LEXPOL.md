# Du projet d'arrêté à l'acte Lexpol via Mes-Démarches

Guide destiné à **Claude**. Il décrit comment, à partir d'un **projet d'arrêté** (PDF ou Word), aligner un formulaire Mes-Démarches et un modèle Lexpol, puis vérifier par des dossiers de test que l'acte généré est correct.
Il est tiré du premier chantier mené ainsi (démarche 3558 et modèle Lexpol 630543, octobre 2026), cité ici seulement comme exemple.

---

## 0. Périmètre et règles absolues

**C'est l'utilisateur qui fait :**
- la création de la démarche Mes-Démarches ;
- la création du modèle Lexpol, et son rattachement au champ Lexpol de la démarche ;
- la mise en production : publication, déploiement, communication. **Claude ne fait jamais de mise en production.**

**Claude ne touche jamais à :**
- les visas, ampliations, transmissions, copies, attendus (« Vu… »), signataires et circuit de validation dans Lexpol ;
- le modèle Lexpol **avant validation explicite**.

**Règle de méthode, sans exception : toute modification passe d'abord par un dossier Lexpol de test.**
1. On corrige un **dossier de test**, reconnaissable à son **NOR qui commence par `ZZZ`** (par exemple ZZZ26000726TT) et à son « Modèle utilisé » égal au modèle visé.
2. L'utilisateur génère et contrôle le PDF, puis **valide**.
3. On reporte dans le **modèle** exactement, et **uniquement**, les modifications validées, avec le même contrôle préalable (segments identiques).
- **Garde-fou** : ne jamais modifier un dossier dont le NOR ne commence pas par `ZZZ` (un acte réel), ni le modèle directement.

**Hors du périmètre de ce guide** : la configuration YAML du robot inspecteur. Claude s'en occupe régulièrement, mais elle n'est pas nécessaire ici et fera l'objet d'un guide distinct.

**Claude peut, avec l'accord de l'utilisateur :**
- analyser le projet d'arrêté et proposer les champs et les variables ;
- ajuster les champs du formulaire Mes-Démarches : libellés, types, options, conditions, caractère obligatoire ;
- créer, remplir et déposer des dossiers de test ; créer ou mettre à jour leur dossier Lexpol depuis l'annotation ;
- corriger un dossier Lexpol de test (variables, articles), puis le modèle après validation.

**Chaque demande d'accord** comporte un tableau risque / probabilité / conséquence / parade, et dit ce qui est irréversible.

---

## 1. Le processus en 6 étapes

```
1. Projet d'arrêté (PDF/Word) fourni par l'utilisateur
   ▼
2. Identification des variables présentes dans le projet d'arrêté
   ▼
3. Mise à jour des champs nécessaires dans Mes-Démarches
   ▼
4. Mise à jour des variables Lexpol
   ▼
5. Mise à jour des textes du modèle avec les variables créées
   ▼
6. Édition du fichier (PDF) et comparaison avec le projet d'arrêté de départ
```

Le fil technique qui relie ces étapes :
`champ Mes-Démarches` → annotation Lexpol (« Prévisualiser les variables ») → `variable Lexpol` → `{@variable@}` dans le texte du modèle → PDF.

**Règle d'or : le libellé exact d'un champ Mes-Démarches devient le nom de la variable Lexpol.** Le moindre écart casse la liaison, une apostrophe ’ au lieu de ' comprise.

### 1 bis. Quel outil pour quoi : Playwright ou accès direct

Principe : **utiliser l'accès direct chaque fois qu'il existe** (API, fichiers locaux), et **Playwright seulement quand il n'y a pas d'autre voie**. Playwright agit dans le navigateur, dans la session de l'utilisateur. Il est plus lent, demande des connexions, et laisse des captures sur le disque.

| Besoin | Outil | Détail |
|---|---|---|
| **Tout ce qui touche Lexpol** : lire ou modifier un dossier ou un modèle, ses variables, ses articles, générer le PDF | **Playwright, toujours** | Lexpol n'a pas d'API accessible. Connexion faite par l'utilisateur. |
| Lire la **structure** d'une démarche Mes-Démarches (champs, types, options, obligation) | **API GraphQL**, sans navigateur | `bin/describe_demarche <n°>`, ou un script `bin/rails runner` avec `MesDemarches::Client` et `MesDemarches::Queries::DemarcheRevision` |
| Lire un **dossier** : valeurs des champs, demandeur, données du Numéro Tahiti (`SiretChamp.etablissement.entreprise…`), annotations | **API GraphQL** | requête ad hoc via `MesDemarches::Client.parse`. Introspection du schéma : `MesDemarches::Schema.types[...]` |
| Retrouver l'**acte Lexpol d'un dossier** : NOR, statut, **lien Lexpol** (`LexpolChamp.dossierUrl`) | **API GraphQL** | évite d'ouvrir la page des annotations |
| Lister les dossiers d'une démarche et leur état | **API GraphQL** | `demarche.dossiers(last: N)` |
| **Modifier le formulaire** (champs, libellés, conditions, obligation) | **Playwright** | l'API ne permet pas d'éditer la démarche |
| Créer, remplir, **déposer** un dossier de test | **Playwright** | parcours usager |
| « **Créer / Mettre à jour le dossier Lexpol** » et « **Prévisualiser les variables** » | **Playwright** | non exposés par l'API |
| **Paramétrage du champ Lexpol** : modèle sélectionné, zone « Variables Lexpol », **liste des variables disponibles** | **Playwright**, en lecture | `…/admin/procedures/<n°>/annotations`, champ de type Lexpol, puis « Afficher les variables disponibles ». L'écriture reste réservée à l'utilisateur, sauf accord explicite |
| Écrire une **annotation privée** | API (mutations GraphQL, déjà utilisées par le robot) ou Playwright | toujours avec l'accord de l'utilisateur ; non nécessaire dans ce processus |
| Lire le **projet d'arrêté** et les **guides PDF** | outil de lecture de fichiers, **page par page, images comprises** | une extraction de texte (`pdftotext`) ne suffit pas pour les PDF faits d'images |
| Fichiers locaux, scripts, ce guide | outils de fichiers et shell | |

Les scripts d'API se placent dans le dossier temporaire de session, et les scripts Playwright réutilisables dans `.playwright-mcp/`, qui est ignoré par git.

#### Boîte à outils d'accès direct (dépôt `inspecteur-mes-demarches`)

Ces méthodes sont **bien plus rapides et plus fiables que Playwright** : pas de navigateur, pas de connexion à faire, pas de lenteur d'interface. On les lance depuis la racine du dépôt. Le jeton d'accès vient du `.env` (`GRAPHQL_BEARER`) : ne jamais l'afficher.

| Méthode | Usage | Exemple |
|---|---|---|
| `bin/describe_demarche <n°>` | structure lisible d'une démarche : sections, champs, types, obligation, options (5 premières), annotations | `bin/describe_demarche 3558` (doc : `bin/README_describe_demarche.md`) |
| `bin/rails runner <script.rb>` | exécuter un script Ruby avec l'application chargée, donc le client GraphQL prêt à l'emploi | voir les gabarits ci-dessous |
| `MesDemarches.query(MesDemarches::Queries::<Nom>, variables: {…})` | requêtes **prédéfinies** de `app/lib/mes_demarches.rb` : `Demarche`, `DemarcheRevision` (structure complète, brouillon et publiée), `Dossier` (un dossier complet), `DossierState`, `DossierId`, `DossiersModifies` (dossiers modifiés depuis une date), `Instructeurs`, `Ping` | `MesDemarches.query(MesDemarches::Queries::DemarcheRevision, variables: { demarche: 3558 })` |
| `MesDemarches::Client.parse(<<~GQL)` puis `MesDemarches::Client.query(...)` | requête **ad hoc**, assignée à une **constante** (contrainte de graphql-client) | `Q = MesDemarches::Client.parse('query { dossier(number: 687751) { annotations { __typename ... on LexpolChamp { nor status dossierUrl } } } }')` |
| `MesDemarches::Schema.types['Type'].fields` | **introspection** du schéma, pour connaître les champs disponibles avant d'écrire une requête | `MesDemarches::Schema.types['SiretChamp']`, `['PersonnePhysique']`, `['LexpolChamp']`, `['Civilite'].values` |
| `bundle exec rake "dossiers:check[<n°>]"` | rejouer les contrôles du robot sur **un** dossier | hors processus Lexpol, mais utile pour un dossier de test |
| `bundle exec rake demarches:list_fields` | lister les champs des démarches citées dans les configurations | |
| Mutations d'annotation (`SetText`, `SetCheckBox`, `SetDate`…, dans `app/lib`) | écrire une annotation privée sans navigateur | **uniquement avec l'accord** de l'utilisateur |

**Gabarits utiles, testés pendant le chantier 3558 :**
- **Sauvegarde complète d'une démarche**, en JSON et en Markdown avec toutes les options : `DemarcheRevision`, puis `JSON.pretty_generate(d.to_h)`.
- **Comparer avant/après** une modification du formulaire : deux sauvegardes, puis un diff des libellés et des `required` par `id`.
- **Valeurs d'un dossier** et **données d'entreprise du Numéro Tahiti** : `dossier(number:) { champs { ... on SiretChamp { etablissement { siret entreprise { raisonSociale nomCommercial formeJuridique } } } } }`. La liste des champs disponibles s'obtient par introspection.
- **Actes Lexpol de tous les dossiers d'une démarche** : `demarche(number:) { dossiers(last: 15) { nodes { number state annotations { ... on LexpolChamp { nor status champDescriptorId updatedAt } } } } }`. C'est ainsi qu'on a vu que T4 avait changé de NOR, donc de modèle.
- **Ce que l'API ne donne pas** : les conditions d'affichage des champs, le **paramétrage du champ Lexpol** (modèle sélectionné, zone « Variables Lexpol », liste des variables disponibles), et les valeurs envoyées (« Prévisualiser les variables »). Pour tout cela, il faut passer par Playwright.

---

## 2. Déroulé détaillé

### Étape 1 : le projet d'arrêté
- Lire le PDF ou le Word en entier, et garder ce document comme **référence de comparaison** pour l'étape 6.
- Si un modèle Lexpol existe déjà, relever son texte actuel (intitulé, articles, tableaux) pour savoir ce qui change.

### Étape 2 : identifier les variables
- Repérer :
  - les **parties variables** : désignation du demandeur, objet du projet, lieux, dates, listes, modes opératoires… ;
  - les **parties conditionnelles** : une ligne de tableau, un paragraphe ou un article qui n'apparaît que dans certains cas.
- **Consulter d'abord la liste des variables disponibles** : paramétrage du champ Lexpol, puis « Afficher les variables disponibles » (section 3.3). On y lit les noms exacts déjà fournis par Mes-Démarches, champs, identité et métadonnées.
- Pour chacune, déterminer d'où vient la valeur :
  - une variable **déjà disponible** (champ usager, identité du demandeur, métadonnée) ;
  - une donnée **dérivée** d'un champ (hors Numéro Tahiti, désormais envoyé d'office, section 3.1) : à déclarer dans « Variables Lexpol », par l'utilisateur ;
  - un **calcul** (Vrai/Faux) ou une **composition**, à faire dans Lexpol ;
  - un **nouveau champ** à créer dans Mes-Démarches.
- Remplir la **table de correspondance**, et la faire valider par l'utilisateur :

  | Partie de l'arrêté | Champ Mes-Démarches (type, libellé exact, condition) | Variable Lexpol (type, formule) | Emplacement dans l'acte |
  |---|---|---|---|

### Étape 3 : mettre à jour les champs Mes-Démarches
- **Sauvegarder d'abord** la structure de la démarche par GraphQL (`bin/describe_demarche <n°>`, ou un export en JSON et en Markdown des champs, options, descriptions et de l'obligation). L'API ne donne pas les conditions d'affichage.
- Ajuster les champs (section 3), avec l'accord de l'utilisateur.
- Créer un dossier de test, le déposer, et lire **« Prévisualiser les variables »** dans l'annotation Lexpol. C'est **la source de vérité** sur les noms et les valeurs réellement envoyés : ne rien supposer sans l'avoir vu là.

### Étape 4 : mettre à jour les variables Lexpol
- **Avant de créer un acte**, vérifier dans le paramétrage du champ Lexpol (section 3.3) que le **modèle sélectionné** est bien celui sur lequel on travaille.
- Créer le dossier Lexpol de test depuis l'annotation, et vérifier le **« Modèle utilisé : NNNNNN »** et le **NOR en `ZZZ…`**. Le lien du dossier Lexpol s'obtient par l'API (`LexpolChamp.dossierUrl`).
- Dans ce **dossier de test** : créer, renommer ou supprimer les variables, et écrire les formules calculées, en les vérifiant avec « Vérifier la valeur calculée » (section 4.1).

### Étape 5 : mettre à jour les textes avec les variables
- Dans le **dossier de test** d'abord : remplacer les parties variables de l'intitulé et des articles par les `{@variables@}`, et poser les conditions `SI` (section 4.3).
- Faire valider par l'utilisateur, puis reporter **uniquement** les modifications validées dans le **modèle** :
  - **relever d'abord le texte actuel du modèle**, qui sert de sauvegarde pour restaurer ;
  - appliquer les **mêmes** remplacements que dans le dossier, avec un contrôle préalable « segment identique » ;
  - recharger, vérifier, et chercher les variables orphelines.
- **Méthode efficace** : préparer une seule liste numérotée de corrections (texte actuel, texte proposé, règle). L'utilisateur valide les numéros, et la même liste sert au dossier puis au modèle.

### Étape 6 : éditer le fichier et le comparer au projet d'arrêté
- Générer le PDF (« Voir le fichier ») sur des actes couvrant la matrice de tests (section 6). On peut aussi le laisser générer par l'utilisateur, en lui indiquant le rendu attendu (section 8.16). Pour tester le modèle corrigé, l'acte doit être **créé après** la correction.
- **Comparer chaque PDF au projet d'arrêté de départ**, partie par partie :
  - texte fixe identique, sans mot perdu ni ajouté ;
  - parties variables remplies, avec le bon format (majuscules, dates, listes) ;
  - parties conditionnelles présentes ou absentes selon le cas, sans ligne ni paragraphe vide ;
  - aucune `{@…@}` restante ;
  - respect des **règles de rédaction** (section 4.7) : majuscules, italique des navires, espaces insécables, ponctuation des listes, montants.
- Présenter les écarts à l'utilisateur dans un tableau (partie · attendu selon le projet · obtenu dans le PDF · cause probable · correction proposée).
- **Nettoyer** : lister les actes et dossiers de test pour l'utilisateur, purger les captures Playwright, se déconnecter.

---

## 3. Mes-Démarches

### 3.1 Ce qui est réellement envoyé à Lexpol

Ces règles ont été constatées dans la prévisualisation, et non dans la documentation. À revérifier sur chaque démarche.

| Donnée | Nom de la variable envoyée | Valeur |
|---|---|---|
| Civilité (étape Identité) | `Demandeur civilité` (et `Civilité`) | `M.` / `Mme`, déjà abrégée |
| Prénom, Nom (étape Identité) | `Demandeur prénom`, `Demandeur nom` (et `Prénom`, `Nom`) | tels que saisis |
| E-mail du demandeur | `Demandeur email` | |
| Mandataire | `Nom du mandataire`, `Prénom du mandataire`, `Dépôt pour un tiers` | |
| Champ **Oui/Non** | libellé du champ | `true` / `false` (jamais « Oui » ni « Non ») |
| **Case à cocher** | libellé du champ | `true` ou vide |
| **Choix multiple** | libellé du champ | `A, B et C` |
| | `<libellé> (liste)` | liste HTML `<ul><li>A ;</li>…</ul>` |
| Date | libellé du champ | `jj/mm/aaaa` |
| **Titre de section** | libellé de la section | résumé des champs de la section |
| **Numéro Tahiti** (Siret) | libellé du champ | le numéro seul (ex. `031864001`) |
| | `<libellé> – Entreprise SIREN`, `<libellé> – Entreprise date de création`, `<libellé> – Entreprise forme juridique`, `<libellé> – Entreprise nom commercial`, `<libellé> – Entreprise raison sociale`, `<libellé> – Libellé NAF` | données du registre, **envoyées d'office** depuis un correctif de Mes-Démarches : plus besoin de les déclarer dans « Variables Lexpol ». Séparateur : **tiret demi-cadratin « – »** entouré d'espaces, à reproduire exactement dans le nom de la variable Lexpol |
| Bloc répétable | libellé du bloc | tableau HTML |
| Métadonnées | `Date de dépôt`, `État du dossier`, `Groupe instructeur`, `Motivation de la décision`… | |

Côté API GraphQL, les mêmes données existent sous d'autres noms : `dossier.demandeur` (`civilite` = `M`/`Mme` non abrégé, `prenom`, `nom`, `dateDeNaissance`) et les données d'entreprise du Numéro Tahiti (`etablissement.entreprise.raisonSociale`…). Ce sont ces noms qui servent à **lire** un dossier par l'API. Ils ne correspondent **pas** aux noms des variables Lexpol : pour Lexpol, seuls comptent les noms de la liste « variables disponibles » et les déclarations de la zone « Variables Lexpol ».

### 3.2 Pièges du formulaire

- **Une case à cocher seule « obligatoire » doit être cochée** pour déposer. Une case de choix (une option parmi d'autres) ne doit jamais être obligatoire.
- **Un choix multiple de 4 options ou moins** s'affiche en **cases à cocher**.
- **Les apostrophes** : Lexpol convertit ’ en ' dans le texte des articles. Utiliser l'**apostrophe droite** partout, dans les libellés comme dans les noms de variables.
- **Les fautes de frappe dans les options** passent telles quelles dans l'acte. Les signaler à l'utilisateur, sans corriger sans accord.
- **Les conditions d'affichage** se posent champ par champ. Dans la 3558, chaque champ porte sa propre condition (« Baleines Est Oui »), y compris derrière un titre de section conditionné. L'effet d'une condition posée sur le seul titre n'a pas été vérifié : faire de même par prudence.
- **Dans un formulaire, deux libellés identiques** (« Numéro de téléphone » en double, par exemple) produiraient deux variables du même nom. Ce n'est pas vérifié, mais c'est à éviter.
- **Une donnée masquée par une condition** arrive vide dans Lexpol. Vérifier, **cas d'usage par cas d'usage**, que chaque variable dont l'acte a besoin est alimentée. Exemple : pour une personne morale résidente, la 3558 n'affiche que le Numéro Tahiti : la raison sociale vient alors de `Numéro Tahiti – Entreprise raison sociale` (ou d'une déclaration dans « Variables Lexpol » sur les modèles antérieurs au correctif).
- **Un dossier en construction modifié** n'est transmis qu'après **« Déposer les modifications »**.
- **Une démarche « en test »** : les dossiers de test ont survécu aux modifications de champs, mais le bandeau prévient qu'ils peuvent être supprimés.

### 3.3 Le champ Lexpol (annotation privée)

**Paramétrage du champ, à consulter à chaque chantier** (Administration → démarche → Annotations privées → le champ de type « Lexpol ») :

| Réglage | Rôle | À retenir |
|---|---|---|
| **Sélectionner un modèle Lexpol** | le modèle à partir duquel les actes sont créés | c'est **ici** qu'on voit et qu'on règle le modèle, que l'API n'expose pas. Le libellé affiché est le **nom** du modèle (ex. « 2025-Dérogation prise de vu et de son_mes_démarches »), pas son numéro : le faire correspondre au « Modèle utilisé : NNNNNN » d'un acte de test |
| **Variables Lexpol** (zone de texte) | **variables supplémentaires** calculées à partir des données du dossier, une par ligne : `chemin de la donnée = nom de la variable Lexpol` | **N'est plus nécessaire pour le Numéro Tahiti**, dont les données arrivent d'office (section 3.1). Reste utile pour **renommer** une donnée en un nom court, ou pour une autre donnée dérivée. Exemple historique de la 3558 : `Numéro Tahiti.etablissement.entreprise_raison_sociale = Raison sociale` et `Numéro Tahiti.etablissement.entreprise_nom_commercial = Nom commercial`. **Le chemin part du libellé du champ**, puis suit la structure des données (`etablissement.entreprise_…`) |
| **Afficher les variables disponibles** | la **liste de toutes les variables** que ce champ peut envoyer à Lexpol : champs, métadonnées, identité… | à **consulter en premier**, dès l'étape 2, pour savoir quels noms existent avant de créer une variable dans Lexpol |
| Logique conditionnelle | condition d'affichage du champ Lexpol lui-même | |

- **Lecture** : ce paramétrage est en lecture libre (bouton « Afficher les variables disponibles »).
- **Écriture** : modifier le modèle sélectionné ou la zone « Variables Lexpol » **change ce que reçoivent tous les futurs actes**. C'est donc toujours avec l'accord de l'utilisateur, et en général c'est lui qui le fait (section 0). Un changement de modèle explique le changement de NOR à la mise à jour, constaté le 20/10.
- **Les chemins possibles** pour la zone « Variables Lexpol » s'obtiennent par **introspection GraphQL** du type du champ, par exemple `SiretChamp → etablissement (PersonneMorale) → entreprise (Entreprise) → raisonSociale, nomCommercial, formeJuridique…`. La syntaxe observée met des tirets bas (`entreprise_raison_sociale`), donc pas exactement le nom GraphQL. **Faire valider** chaque nouveau chemin par un test dans la prévisualisation.

- « **Créer le dossier Lexpol** » (lien `…/champs/<dossier>/<champ>/lexpol/upsert`) crée un dossier à partir du **modèle configuré**.
- « **Mettre à jour le dossier Lexpol** » renvoie les **valeurs**, sans recharger le texte du modèle. **Si le modèle configuré a changé, il crée un nouveau dossier Lexpol** (nouveau NOR).
- « **Prévisualiser les variables** » est en lecture seule : la liste complète de ce qui sera envoyé.
- L'API GraphQL n'expose **pas** le modèle configuré. On le voit dans l'administration de la démarche, ou dans Lexpol (« Modèle utilisé »). Si le modèle d'un nouvel acte n'est pas celui attendu : s'arrêter et prévenir l'utilisateur.

---

## 4. Lexpol / GEDA

### 4.1 Variables

- Types : **Texte**, **Montant**, **Vrai/Faux**, **Vrai/Faux à valeur calculée**.
- Une valeur `true`/`false` venant de Mes-Démarches se reçoit :
  - **directement dans une variable Vrai/Faux**. C'est vérifié pour les cases à cocher (`Baleines`, `Drone`…), qui s'utilisent alors directement dans `{@SI_…@}` et dans les conditions d'article ;
  - ou dans une variable **Texte**, testée ensuite par formule. C'est ce qu'on a fait pour les Oui/Non `Résident` et `Personne morale ?`.
- **Formules calculées** : `ET(a;b;…)`, `OU(a;b;…)`, `NON(a)`, avec le **point-virgule** comme séparateur. Les comparaisons s'écrivent `{@var@}="valeur"`, `<`, `>`, `<=`, `>=`. Exemples :
  - `{@Résident@}="true"`
  - `NON({@Personne morale ?@}="true")`
  - `ET({@Personne morale ?@}="true";{@Résident@}="true")`
- **Avant d'enregistrer, toujours cliquer sur « Vérifier la valeur calculée »** : la vérification ne sauvegarde rien, et renvoie « Syntaxe correcte, valeur calculée : VRAI/FAUX ».
- Pour modifier une formule, deux voies : la fenêtre de la variable (icône calculatrice, `modifierVariableCalculee(id)`) propose un bouton « Enregistrer », mais cette voie n'a pas encore été testée. Sinon, **supprimer puis recréer** la variable, ce qui est testé et garde le même nom, donc les textes restent valides.
- **Une variable Texte peut contenir un bloc conditionnel et d'autres variables.** C'est testé, et ça fonctionne, alors que le guide GEDA interdit `@ { } ;` dans une valeur. **Toujours tester plutôt que se fier au guide.**
- **Formats** : `:majuscules`, `:minuscules`, `:prem_majuscule`, `:prem_minuscule`, `:minuscules_prem_majuscule`, `:date_en_lettres`.
- **Enchaîner deux formats** :
  - `{@x@:minuscules:prem_majuscule}` **ne fonctionne pas** (testé) ;
  - il faut passer par une **variable intermédiaire**. Lexpol résout d'abord les variables contenues, **puis** applique le format. Exemple testé : une variable Texte `raison sociale minuscules` = `{@Raison sociale@:minuscules}`, puis `{@raison sociale minuscules@:prem_majuscule}`, ce qui donne « Electricite de tahiti ».
  - C'est le même mécanisme qui permet `demandeur debut de phrase` = `{@demandeur milieu de phrase@:prem_majuscule}` : « La société… » en début de phrase (section 4.2).
- **Aucun format dans les textes de l'acte pour les variables de composition** : écrire `{@demandeur debut de phrase@}`, jamais `{@demandeur milieu de phrase@:prem_majuscule}`. Si l'utilisateur corrige à la main la valeur de la variable dans le dossier (un accent dans une raison sociale, par exemple), un format posé dans le texte s'appliquerait encore par-dessus et déferait sa correction. **La mise en forme se fait dans la valeur de la variable**, jamais dans le texte.
- **Nom de variable** : ni `@ / { } ;`, ni espace collée aux `@`.
- **Convention de nommage** :
  - une variable **alimentée** par Mes-Démarches porte le **libellé exact** du champ ;
  - une variable **calculée** porte un nom en minuscules **suffixé par `_`** (`personne_morale_`) ;
  - une variable de **composition** porte un nom explicite (`demandeur milieu de phrase`, `demandeur debut de phrase`).

### 4.2 Modèle générique : désignation du demandeur

Deux variables Texte, **une par position dans la phrase**, utilisées **sans format** dans les textes (section 4.1).

`demandeur milieu de phrase` :

```
{@SI_personne_morale_@}la société {@Raison sociale@:minuscules_prem_majuscule}{@/SI_personne_morale_@}{@SI_personne_physique_@}{@Demandeur civilité@}[espace insécable]{@Demandeur prénom@:minuscules_prem_majuscule} {@Demandeur nom@:majuscules}{@/SI_personne_physique_@}
```

`demandeur debut de phrase` :

```
{@demandeur milieu de phrase@:prem_majuscule}
```

- `personne_morale_` = `{@Personne morale ?@}="true"`
- `personne_physique_` = `NON({@Personne morale ?@}="true")`. On pourrait aussi écrire `{@SI_NON_personne_morale_@}`, voir la section 4.6.
- `{@Raison sociale@:minuscules_prem_majuscule}` donne « Electricite De Tahiti » (choix de l'utilisateur, section 4.7). L'accent ne se devine pas : il se corrige à la main dans la valeur de la variable du dossier.
- Milieu de phrase : `{@demandeur milieu de phrase@}` (intitulé). Début de phrase : `{@demandeur debut de phrase@}` (article 1).
- Si l'utilisateur corrige `demandeur milieu de phrase` dans un dossier, `demandeur debut de phrase` reprend sa correction avec une majuscule initiale. S'il corrige `demandeur debut de phrase`, sa valeur remplace la formule.
- Le cas personne physique (« M. Prénom NOM ») reste à valider dans un PDF.
- Règles de rédaction : « Prénom NOM », c'est-à-dire le prénom avec une majuscule initiale et le nom en capitales ; civilité abrégée (M., Mme) ; espace insécable après la civilité.

### 4.3 Conditions SI sans lignes vides

Lexpol supprime **tout le texte compris entre `{@SI_x@}` et `{@/SI_x@}`**, balises HTML comprises.

**Ligne de tableau conditionnelle.** Ne pas mettre les balises dans la première et la dernière cellule : il resterait `<tr><td></td></tr>`, donc une ligne vide.
- `{@SI_x@}` va à la **fin de la dernière cellule de la ligne précédente** ;
- `{@/SI_x@}` va à la **fin de la dernière cellule de la ligne concernée**.

```
| En-tête 1 | … | En-tête N{@SI_A@}                    |
| Ligne A   | … | valeur A{@/SI_A@}{@SI_B@}            |
| Ligne B   | … | valeur B{@/SI_B@}                    |
```

**Liste de paragraphes conditionnels** : même principe.
```
<p>Introduction :{@SI_X@}</p><p>- élément X{@/SI_X@}{@SI_Y@}</p><p>- élément Y{@/SI_Y@}</p>
```

Retirer aussi toute **hauteur fixe** du tableau (`height:` en style). Après toute modification d'un tableau conditionnel, revérifier que chaque `{@SI_…@}` reste bien collé à la fin de la ligne précédente.

### 4.4 Modèle, dossier et vérification

- Un dossier Lexpol est une **copie figée** du modèle à sa création. Les corrections du modèle ne s'y reportent pas, et « Mettre à jour » ne recharge que les valeurs.
- Pour tester une correction du modèle, il faut un **nouvel** acte. Pour tester une idée sans toucher au modèle, on corrige un **dossier** de test.
- **Contrôle d'un dossier ou d'un modèle :**
  - la liste des variables : doublons, noms, types ;
  - la recherche des **variables orphelines**, c'est-à-dire tout `{@…@}` du texte sans variable correspondante, hors variables internes de Lexpol (liste en section 4.6), et hors mots-clés `SINON`, `SI_`, `SI_NON_` ;
  - le PDF, où il ne doit rester aucun `{@…@}`.

### 4.5 Mécanique de l'interface (automatisation Playwright, générique)

Identifiants : `idw` est l'identifiant du dossier ou du modèle dans l'URL (`geda_dossier.php?idw=…`). `ide` est l'identifiant de l'élément « acte », visible dans les identifiants HTML, par exemple `article<ide>_<bloc>_<n>_txt`.

- **Ouvrir l'édition** : cliquer sur « Modifier le contenu de l'acte » **seulement s'il est visible**, car il est masqué quand l'édition est déjà ouverte et un clic ferait échouer le script. Attendre ensuite que `[id^="variableCodeEdit"]` soit présent.
- **Modifier la valeur d'une variable Texte** (testé) : `activeModifVariable(id,false)`, puis remplir `#variableEdit<id> .data_form`, puis `blur` et un clic ailleurs. Vérifier qu'une requête `variables_modifier` part, puis relire la valeur après rechargement.
- **Articles** (éditeur Summernote) :
  - écrire : `jQuery('#article<ide>_<bloc>_<n>_txt').summernote('code', html)` ;
  - **enregistrer** : ouvrir l'éditeur avec `EditerModeleArticle(ide,bloc,n)`, cliquer dans `#article…_contenu .note-editable`, puis cliquer **en dehors**. L'enregistrement se fait à la sortie de l'éditeur. Vérifier qu'une requête `modifiercontenuarticle` part ;
  - **piège constaté le 21/10** : une requête `modifiercontenuarticle` peut partir avec **l'ancien** contenu. Ce qui fonctionne : ouvrir l'éditeur, **puis** écrire (`summernote('code', html)`), contrôler que `#article…_contenu .note-editable` contient bien le nouveau texte, cliquer dedans, puis en dehors. Un enregistrement réussi est suivi de `elementarticlehtmlget`. Toujours relire après rechargement ;
  - le bouton « Editer / Enregistrer » ne fait qu'ouvrir et fermer l'éditeur : il n'enregistre pas ;
  - ne jamais ouvrir l'éditeur de **titre** (`modifier_titre_article`) et celui de **contenu** du même article en même temps, car ils se ferment l'un l'autre ;
  - garde-fou : relire la valeur actuelle, **ne remplacer qu'un segment exact**, et s'arrêter s'il est introuvable.
- **Intitulé** : `element_intitule_modifier(ide)`, puis on écrit dans `#intitule_element_<ide>_edit_txt` (Summernote et `.val()`), puis `element_intitule_save(ide)`.
- **Insérer un article** : `CreerModeleArticle(ide,bloc,n,'ARTICLE','AP')` insère après l'article `n`. Les numéros suivants se décalent.
- **Variables** :
  - ouvrir le panneau : `AfficherMasquerZone(true,'divVariables')` ;
  - **renommer** : `activeModifVariable(id,true)`, saisir le nouveau nom dans `#variableCodeEdit<id> input.data_form`, puis Entrée ;
  - **créer** : cliquer sur le bouton `ajouterVariable(idw)`, puis dans la fenêtre visible renseigner `#type-variable` (STRING, MONTANT ou CHECKBOX), `#code-variable` et la valeur. Pour une valeur calculée : `#valVariableCHECKBOX` = `COND` et la formule dans `#conditionVariableCheckbox`. Cliquer ensuite sur `#calculerVariable`, puis `#valider-variable`, puis **`jQuery.modal.close()`** : sans cette fermeture, la fenêtre suivante plante ;
  - les fenêtres fermées restent dans la page : cibler `>> visible=true` ;
  - **supprimer** : `variable_supprimer(idw,id)` (équivalent du « Oui » de confirmation). Le panneau se recharge, et parfois **se vide**. Il faut alors **recharger la page et traiter une variable à la fois**, puis relire la liste.
  - **lire une formule** : `modifierVariableCalculee(id)` ouvre la fenêtre, on lit la formule, puis on ferme sans enregistrer.
- **PDF** : « Voir le fichier » ouvre `geda_getFichier.php?id=…`.
- **Lenteurs** : Lexpol peut dépasser 30 s par page. Utiliser `waitUntil: 'domcontentloaded'`, des délais de 60 à 90 s, et vérifier l'état réel après chaque lot.
- **Alertes** « Une erreur est intervenue » : les fermer, puis relire l'état avant de continuer.

### 4.6 Ce que dit la documentation officielle GEDA

Sources fournies par l'utilisateur : « Guide utilisation Plateforme GEDA Variables.pdf » (pages 87 à 98) et « GEDA Variables.pdf » (pages 151 à 160), SGG, 16 octobre 2026. Ces PDF sont faits d'**images** : il faut les lire page par page, une extraction de texte ne suffit pas.

**Deux manières de conditionner, combinables :**

1. **Les zones conditionnées** : une condition posée sur un **élément entier**, via l'icône « C » de l'élément, puis la fenêtre « **Gérer une condition** ». On y choisit une variable Vrai/Faux.
   - Éléments concernés : attendus (Vu), **articles**, références, pièces jointes, zones de contenu.
   - Couleur de l'icône : grise sans condition, **verte** si la condition vaut Vrai (l'élément s'affiche), **rouge** si elle vaut Faux (il ne s'affiche pas). Une infobulle indique la variable utilisée.
   - C'est la bonne voie pour **afficher ou non un article complet** (par exemple « Modalités d'approche des baleines » seulement si `Baleines`), plutôt qu'un `SI` dans le texte. Les attendus restent hors du périmètre de Claude (section 0).
2. **La syntaxe SI dans le texte**, **uniquement avec des variables Vrai/Faux** :

   | Syntaxe | Effet |
   |---|---|
   | `{@SI_x@}texte{@/SI_x@}` | texte affiché si x est Vrai |
   | `{@SI_x@}texte A{@SINON@}texte B{@/SI_x@}` | A si Vrai, sinon B |
   | `{@SI_NON_x@}texte{@/SI_NON_x@}` | texte affiché si x est **Faux** |
   | `{@SI_NON_x@}A{@SINON@}B{@/SI_NON_x@}` | A si Faux, sinon B |

   - Une syntaxe incomplète (un `SI_` ou un `/SI_` oublié) ne fonctionne pas.
   - L'icône de copie d'une variable Vrai/Faux propose ces 5 syntaxes, prêtes à coller.
   - **Conséquence pour nos modèles** : une variable « contraire » comme `personne_physique_` = `NON(…)` peut être remplacée par `{@SI_NON_personne_morale_@}`, ou par un `{@SINON@}`. C'est plus simple, mais le changement est à proposer et à faire valider.

**Variables calculées** (p. 158 à 160) :
- fonctions `ET`, `OU`, `NON`, combinables ; séparateur `;` ;
- opérateurs `>`, `<`, `>=`, `<=`, et `=` pour les types **Montant** et **Texte** ;
- usages : `{@variable@}` (booléenne seule), `{@montant@}>10`, `{@texte@}="Monsieur"` ;
- cas pratique type : une variable Montant, puis une Vrai/Faux calculée `{@montant@}>=1000000`, qui conditionne un attendu.

**Types et paramétrage** (p. 87 à 91) :
- **Texte**, **Montant** et **Vrai/Faux**.
- Une variable **Montant** crée automatiquement `<nom>_en_lettres`. Règles d'écriture :
  - en chiffres : « … F CFP », avec une espace insécable entre F et CFP ;
  - en lettres : « … francs CFP », avec une espace insécable, ni en majuscules ni en italique.
- **Données personnelles** : il est **obligatoire** d'utiliser des variables pour les montants et pour les données personnelles des personnes physiques (prénom, NOM…). À la création d'une variable Texte, la case « **Cochez s'il s'agit d'une donnée personnelle** » doit être cochée pour ces données. Elle se modifie ensuite avec l'icône « Indiquer une donnée personnelle ». Cette case est à cocher pour `Demandeur prénom` et `Demandeur nom`, mais **ce n'a pas été fait** dans le chantier 3558 : à proposer.
- **Paramétrage** (icône engrenage) :
  - **Libre**, le défaut : la variable peut être supprimée ou laissée vide dans le futur dossier ;
  - **Non supprimable** : elle peut rester vide ;
  - **Obligatoire** : le dossier ne passe pas au niveau suivant tant qu'elle est vide.
- **Valeurs génériques** : dans un modèle, il est conseillé de mettre des valeurs génériques, par exemple « (NOM BENEFICIAIRE) », pour éviter les erreurs. Les vraies valeurs viennent avec le dossier NOR.
- Pour certains champs, il faut **actualiser la page** pour voir une nouvelle valeur.

**Écriture dans les textes** (p. 92 à 98) :
- copier le nom avec l'icône de copie, puis faire Ctrl+V ;
- **gras, italique, souligné** : sélectionner le nom **accolades comprises**, puis appliquer la mise en forme ;
- **intitulé de l'arrêté** :
  - il ne commence pas par « Arrêté », mais par « portant », « relatif », « attribuant »… ;
  - GEDA met la première lettre en minuscule et supprime le point final ;
  - un retour chariot suivi de REGULARISATION centre ce mot, entouré de tirets ;
- les actes respectent la **charte orthotypographique de la Polynésie française** ;
- « Voir le fichier avec ampliation » existe aussi, à côté de « Voir le fichier ».

**Variables internes de Lexpol** (p. 94-95, gérées par le SGG, non modifiables) : `STRUCTURE`, `STRUCTURE_SIGLE`, `STRUCTURE_PIED_PAGE`, `STRUCTURE_RESPONSABLE*`, `MINISTERE_TEXTE_ATTRIBUTION`, `STRUCTURE_TEXTE_CREATION`, `STRUCTURE_TEXTE_ORGANISATION`, `RESPONSABLE_TEXTE_NOMINATION`, `RESPONSABLE_TEXTE_DELEGATION`, `APF_/CESEC_/APC_/HC_DESTINATAIRE`, `NUM_ARRETE_BC` et `DATE_ARRETE_BC` (après enregistrement par le BC), `EXEC` (article d'exécution), `SIGLE_SERVICE`, `SIGLE_MINISTERE`. La liste complète s'obtient avec l'icône « Variables Lexpol ». Une valeur que GEDA n'a pas pu déterminer reste vide.

**Ce que la pratique contredit ou précise** :
- La documentation interdit `@ { } ;` dans une **valeur**. Une variable Texte de composition contenant des `{@SI_…@}` fonctionne pourtant (section 4.2).
- Elle ne parle pas des **lignes vides** laissées par un `SI` dans un tableau (section 4.3).

### 4.7 Règles de rédaction (charte orthotypographique, guide SGG p. 57-58)

À appliquer **dans les textes du modèle** et à **contrôler à l'étape 6**, lors de la comparaison du PDF.

| Élément | Règle | Conséquence pour les variables et les formats |
|---|---|---|
| Majuscules en général | pas d'expressions entières en majuscules, sauf sigles, acronymes et noms de famille | |
| **Personne physique** | prénom(s) d'abord, séparés par une virgule, avec une majuscule initiale. **Nom de famille entièrement en majuscules.** Ex. : « Pierre, Alain, Denis DELOIN », « Mme Sophie DUPUIS épouse BONNET ». Valable aussi pour les entreprises individuelles | `{@Demandeur prénom@:minuscules_prem_majuscule} {@Demandeur nom@:majuscules}`. **À tester** sur un prénom composé (« Jean-Pierre ») : le format ne doit pas donner « Jean-pierre » |
| **Personne morale de droit privé**, navire, projet, événement | **jamais entièrement en majuscules, jamais entre guillemets**. Seuls les premiers caractères des mots distinctifs prennent une majuscule. Ex. : « EURL Super Tours », « GIE Moorea Tourisme » | Une raison sociale reçue en capitales (« ELECTRICITE DE TAHITI ») est **non conforme**. Aucun format n'est parfait, car ni les accents ni les noms propres ne se devinent : `:minuscules_prem_majuscule` donne « Electricite De Tahiti », et la variable intermédiaire (minuscules, puis `:prem_majuscule`) donne « Electricite de tahiti ». **Solution retenue sur la 3558 : `:minuscules_prem_majuscule`** (choix de l'utilisateur le 21/10, après un premier essai avec la variable intermédiaire). L'accent se corrige à la main dans la variable du dossier |
| **Nom de navire** | en *italique*. Ex. : « immatriculation PY XXXXX *Moana III* » | mettre la variable en italique dans le texte, en sélectionnant `{@Nom du navire@}` accolades comprises |
| Archipels, îles, communes, terres, lieux | seul le premier caractère de chaque mot prend une majuscule, sans guillemets. Ex. : « Bora Bora », « lotissement agricole Mutuhionoa » | vérifier les options des listes (Tahiti, Moorea…) |
| Voies | nom propre avec une majuscule, terme générique en minuscule. Ex. : « rue Vénus », « boulevard de la Reine-Pomare-IV » | |
| **Montants** | variable de type **Montant obligatoire**. Chiffres d'abord, puis les lettres entre parenthèses. Traits d'union entre les mots du nombre. « … F CFP » et « … francs CFP » avec une espace insécable. Lettres ni en majuscules ni en italique. Ex. : « 3 000 000 F CFP (trois-millions de francs CFP) » | `{@MONTANT@} F CFP ({@MONTANT_en_lettres@} francs CFP)` |
| Subdivisions | 1er niveau « I - », 2e « A. », 3e « 1° », 4e « a) », avec des espaces insécables | |
| **Listes et énumérations** | phrase introductive terminée par « : » précédé d'une **espace insécable**. Niveaux « 1° » puis « a) ». Le premier mot prend une majuscule, sauf après un tiret. Tirets réservés aux énumérations de personnes, communes, terres. **Chaque élément se termine par « ; » précédé d'une espace insécable, le dernier par un point.** Pas d'interligne entre les éléments | voir la remarque ci-dessous sur les listes conditionnelles |
| Division d'un texte | titres, chapitres, sections, articles. Pas de paragraphes, sauf si l'acte modifié en comporte | |

**Listes conditionnelles et ponctuation.** Avec des éléments conditionnels, on ne sait pas à l'avance lequel sera le dernier : la règle « ; » partout et « . » au dernier est difficile à tenir. Deux pistes, à faire valider :
- une phrase plutôt qu'une liste, en s'appuyant sur une variable de choix multiple que Mes-Démarches envoie déjà sous la forme « A, B et C » ;
- terminer chaque élément par « ; » et accepter l'écart sur le dernier.

**Contrôles à ajouter à l'étape 6** : noms de famille en capitales, dénominations sans capitales intégrales ni guillemets, navires en italique, espaces insécables avant « : » et « ; », ponctuation des listes, montants au bon format.

---

## 5. Dossiers de test Mes-Démarches (automatisation)

- **Scripts** dans `.playwright-mcp/` du dépôt (ignoré par git), écrits pour la 3558 et à adapter à chaque démarche :
  - `remplir-3558.js` : plan passé via `window.__p` (identité, Oui/Non par identifiant, commune, pays, textes, cases, listes, dates) ;
  - `verifier-3558.js` : relit tout après rechargement ;
  - `ajout-champs-3558.js` : ajoute des champs dans l'éditeur de la démarche.
- **Lien de création directe** : `https://www.mes-demarches.gov.pf/dossiers/new?brouillon=true&procedure_id=<n°>`
- **Avant chaque dossier**, relire la structure (le formulaire évolue) et repérer les champs conditionnels qui apparaissent selon les réponses.
- **Pièges** :
  - radios et cases DSFR masquées : cliquer le **libellé** (`label[for=…]`) ;
  - libellés en double (« Oui », « Non ») : cibler par identifiant (`champ-<stable_id>-input-yes|no`) ;
  - listes : taper une partie distinctive (le nom scientifique, par exemple), puis cliquer l'option **visible** ;
  - Numéro Tahiti : saisir le numéro, puis cliquer sur le lien « Sélectionner » de l'établissement (`etablissementsList_pick`), ce qui peut recharger la page ;
  - pièces jointes : `browser_file_upload` avec un fichier **situé sous le dépôt**.
- **Données de test** :
  - identités **fictives**, et **jamais « Claude »** (ni nom, ni texte) ;
  - motivation : « DOSSIER DE TEST - ne pas instruire. » ;
  - personne morale : numéro Tahiti **public** d'une grande entreprise (EDT `031864`, établissement 001), raison sociale fictive « TEST SOCIETE … » ;
  - pièces : PDF factices.

---

## 6. Matrice de tests (à adapter)

| Axe | Cas à couvrir |
|---|---|
| Demandeur | personne physique M. · personne physique Mme · personne morale avec chaque source de raison sociale (saisie, Numéro Tahiti) · résident / non résident |
| Parties conditionnelles | aucune · une seule · plusieurs · toutes |
| Listes multiples | 1 valeur · 2 à 3 · 5 et plus |
| Dates | valeurs limites prévues par l'arrêté |
| Champs facultatifs | renseignés / vides |

**Contrôles dans le PDF** : intitulé, désignation (majuscule en début de phrase), tableaux sans lignes vides, listes conditionnelles, aucune `{@…@}` restante, ponctuation et accords (« autorisé(e) »).

---

## 7. Sécurité et méthode de session

- **Lexpol est un système externe partagé** : chaque action est faite au nom de l'utilisateur, dans sa session. Ne naviguer que sur les pages qu'il a autorisées.
- **Le mode automatique** de Claude Code peut bloquer certaines actions (suppressions, dépôts, « transactions réelles »). Ne pas contourner : demander à l'utilisateur de passer en mode « demande d'approbation » (`Shift+Tab`), ou de faire l'action lui-même.
- **Données** : préférer les dossiers de test. Les captures Playwright contiennent le texte des pages : `.playwright-mcp/` doit rester dans `.gitignore` et être purgé en fin de chantier.
- **Fin de session** : déconnexion de Lexpol et de Mes-Démarches, puis liste des actes et dossiers de test à supprimer, remise à l'utilisateur.

---

## 8. Recettes pas à pas

Chaque recette indique la **voie manuelle**, celle qu'on explique à l'utilisateur, et la **voie automatisée** avec Playwright. Avant toute écriture : demande d'accord avec le tableau des risques.

### 8.1 Adresses utiles

| Où | URL |
|---|---|
| Éditeur des champs usager | `https://www.mes-demarches.gov.pf/admin/procedures/<n°>/champs` |
| Éditeur des annotations privées (dont le champ Lexpol) | `…/admin/procedures/<n°>/annotations` |
| Annotations d'un dossier (côté instructeur) | `…/procedures/<n°>/dossiers/<dossier>/annotations-privees` |
| Nouveau dossier (usager) | `…/dossiers/new?brouillon=true&procedure_id=<n°>` |
| Identité, brouillon, modification d'un dossier | `…/dossiers/<dossier>/identite`, `/brouillon`, `/modifier` |
| Dossier ou modèle Lexpol | `https://lexpol.cloud.pf/extranet/geda_dossier.php?idw=<idw>&hk=<clé>` |
| Déconnexion Lexpol | `https://lexpol.cloud.pf/extranet/logout.php` |

Les sessions expirent (Mes-Démarches comme Lexpol). Si une page de connexion apparaît, **c'est l'utilisateur qui se connecte** dans la fenêtre Chromium : ne jamais saisir ses identifiants.

### 8.2 Sauvegarder la structure d'une démarche
- `bin/describe_demarche <n°>` donne une vue lisible (les options des listes sont tronquées à 5).
- Pour une sauvegarde complète, faire une requête GraphQL `DemarcheRevision` (`MesDemarches::Queries::DemarcheRevision`, avec `published_revision || draft_revision`), puis écrire le JSON brut et un Markdown avec toutes les options. Compter aussi les sous-champs des blocs répétables : le compteur de l'administration les inclut.
- Limite : ni les conditions d'affichage, ni le modèle Lexpol configuré ne sont exposés.

### 8.3 Lire les variables réellement envoyées à Lexpol
1. Ouvrir les annotations privées d'un dossier **déposé**.
2. Cliquer sur « **Prévisualiser les variables** » (bouton `#lexpol-preview-btn`, lecture seule).
3. Relire **toute** la liste, sans filtre sur les noms. Pour vérifier qu'une donnée est envoyée, **chercher sa valeur** (« ELECTRICITE », un numéro…) plutôt que son nom supposé.

### 8.4 Ajouter un champ dans le formulaire Mes-Démarches
- **Manuel** : dans l'éditeur des champs, cliquer sur « Ajouter un champ » sous le champ après lequel insérer, puis choisir le type et saisir le libellé (enregistré à la sortie du champ). Cocher ou décocher « obligatoire », puis poser la condition.
- **Automatisé** (`ajout-champs-3558.js`, à copier et adapter pour une autre démarche) :
  - repérer les éditeurs `[id^="type_de_champ_editor_procedure_revision_type_de_champ_"]` ;
  - le **nouvel** éditeur est celui qui n'existait pas avant le clic ;
  - type : `select[name$="[type_champ]"]` ; libellé : `input[name$="[libelle]"]`, puis `blur` ; obligatoire : cliquer le **libellé** de la case `[mandatory]` ;
  - titre de section : `select[name$="[header_section_level]"]` (« Titre de niveau 2 »).
- **Les listes de choix peuvent rester vides** à la création, si l'utilisateur les remplit ensuite. Ne jamais inventer d'options.

### 8.5 Poser, modifier ou retirer une condition d'affichage
- Dans l'éditeur du champ, le bouton « cliquer pour activer » ouvre la logique conditionnelle. On choisit alors `[targeted_champ]` (le champ cible), `[operator_name]` (« Est ») et `[value]` (« Oui » / « Non »). Chaque choix est enregistré automatiquement.
- « Ajouter une condition » enchaîne une deuxième ligne, avec « Et ».
- Pour **retirer une ligne**, utiliser le bouton de la ligne dont le `formaction` contient `delete_row?row_index=<n>`. Le mode automatique a déjà bloqué cette action : la faire faire à l'utilisateur, ou passer en mode approbation.

### 8.6 Rendre un champ facultatif, ou le renommer
- Facultatif : cliquer le libellé de la case « obligatoire » dans l'éditeur du champ, puis vérifier par l'API (`required`).
- Renommer : remplir `input[name$="[libelle]"]`, puis `blur`. **Renommer un champ change le nom de la variable envoyée** : renommer aussi la variable Lexpol, et ses usages dans les textes.
- Après une modification : relire la structure par l'API, et **comparer avant/après** pour prouver que seul le champ visé a changé.

### 8.7 Créer une variable simple dans Lexpol (Texte, Vrai/Faux)
- **Manuel** : ouvrir l'édition (« Modifier le contenu de l'acte »), puis « Afficher les variables », puis l'icône « Ajouter une variable ». Choisir le type, saisir le nom (sans `{@ @}`) et une valeur facultative, puis cliquer sur Enregistrer.
- **Automatisé** : cliquer sur le bouton `ajouterVariable(<idw>)`. Dans la fenêtre **visible**, renseigner `#type-variable` (`STRING` / `MONTANT` / `CHECKBOX`) et `#code-variable`, puis pour une Vrai/Faux `#valVariableCHECKBOX` = `0` (Faux) ou `1` (Vrai). Cliquer ensuite sur `#valider-variable`, puis **`jQuery.modal.close()`**.
- Dans un modèle, laisser les valeurs vides (ou Faux) : elles seront remplies par Mes-Démarches.

### 8.8 Créer une variable calculée (Vrai/Faux)
- **Manuel** :
  1. « Ajouter une variable », puis Type = **Vrai / Faux**.
  2. Nom, par exemple `personne_morale_`.
  3. Valeur = **« Valeur calculée »**. Une zone de formule apparaît.
  4. Saisir la formule, par exemple `{@Personne morale ?@}="true"`.
  5. Cliquer sur **« Vérifier la valeur calculée »**. Le résultat attendu est « Syntaxe correcte, valeur calculée : VRAI/FAUX ».
  6. Cliquer sur Enregistrer. La variable porte alors une icône calculatrice.
- **Automatisé** : comme en 8.7, avec `#valVariableCHECKBOX` = `COND`, la formule dans `#conditionVariableCheckbox`, puis `#calculerVariable` (lire `#resCalculVariable`), puis `#valider-variable`, puis `jQuery.modal.close()`.
- **Pour tester une formule sur des valeurs réelles** : la vérifier dans un **dossier** de test qui contient des valeurs, ou mettre temporairement une valeur dans la variable source du modèle, puis la vider.
- **Syntaxe** : `ET(a;b)`, `OU(a;b)`, `NON(a)`, `{@var@}="texte"`, `{@montant@}>1000`. Une Vrai/Faux peut s'utiliser seule : `NON({@eng comptable@})`.
- **Calquer les formules sur les valeurs envoyées** (`true`/`false`), et non sur ce que voit l'usager (Oui/Non).
- **Inutile de créer une variable « contraire »** : dans le texte, `{@SI_NON_x@}…{@/SI_NON_x@}` ou `{@SI_x@}…{@SINON@}…{@/SI_x@}` suffisent (section 4.6).

### 8.8 bis Conditionner un article entier
- **Manuel** : dans l'éditeur, cliquer l'icône « C » de l'article, ce qui ouvre « Gérer une condition ». Choisir la variable Vrai/Faux, puis Enregistrer. L'icône devient verte (Vrai) ou rouge (Faux).
- **Automatisé** : l'icône appelle `EditerCondition(this)`, ce qui n'a **pas encore été testé** en écriture. Préférer la voie manuelle par l'utilisateur, ou tester d'abord sur un dossier.
- **Lire les conditions existantes** (testé) : chaque élément a un lien `a.btnCondition`, avec `id="btnCondition_<ide>_<bloc>_<n>"` pour un article. Son attribut **`title`** vaut « Gérer une condition » s'il n'y a pas de condition, ou « **Variable : {@Baleines@} = Vrai** » s'il y en a une ; s'y ajoutent `data-idcondition` (différent de 0) et `data-conditionvaleur="true"`. Les attendus (`…_ATTENDUS_<n>`) et les ampliataires portent le même mécanisme, mais restent hors du périmètre.

### 8.9 Créer une variable de composition (texte conditionnel réutilisable)
- C'est une variable **Texte** dont la valeur contient des `{@SI_…@}` et d'autres `{@variables@}`. Exemple : `demandeur milieu de phrase` (section 4.2).
- On l'utilise ensuite partout avec `{@nom@}`, **sans format** (section 4.1). Pour le début de phrase, une seconde variable de composition (`demandeur debut de phrase`).
- Avantage : une seule définition, réutilisée dans l'intitulé et les articles.

### 8.9 bis Repérer et marquer les données personnelles
- Dans la liste des variables, l'icône « Indiquer une donnée personnelle » (`modifierVariableDonneePersonnelle(id)`) affiche `data_pers.png` si la variable **n'est pas** marquée, et `data_pers_oui.png` si elle l'**est**.
- Contrôle à faire : les variables de prénom, de nom et d'adresse d'une personne physique doivent être marquées. Dans le modèle 630543, `Demandeur prénom` et `Demandeur nom` ne l'étaient pas, ce qui est à proposer à l'utilisateur.

### 8.10 Renommer, chercher les usages, supprimer une variable
- **Renommer** : cliquer sur le nom, le modifier, puis Entrée ou un clic ailleurs (en automatisé : `activeModifVariable(id,true)`). **Lexpol ne répercute pas le nouveau nom dans les textes** : corriger ou recoller le nom partout.
- **Chercher les usages** : l'icône loupe, « Rechercher les emplacements » (`rechercherVariable(idw,id)`). On peut aussi chercher `{@nom@` et `SI_nom@` dans tous les textes (articles, intitulé, attendus).
- **Supprimer** : seulement après avoir vérifié qu'aucun texte ne l'utilise (icône croix, puis confirmation ; en automatisé `variable_supprimer(idw,id)`). Recharger ensuite et relire la liste.
- **Ordre** : les icônes Monter / Descendre (`variable_deplacer(idw,id,±1)`).

### 8.11 Écrire les variables dans un texte (intitulé, article)
- Taper `{@nom exact@}` dans le texte, ou copier le nom avec l'icône de copie puis faire Ctrl+V.
- Vérifier ensuite qu'il n'y a **aucune variable orpheline** (section 4.4).
- Pour un tableau ou une liste conditionnelle : appliquer la section 4.3.
- Lexpol convertit les apostrophes courbes en droites à l'enregistrement : **relire le texte enregistré** (la valeur de la zone de texte après rechargement), pas seulement ce qu'on a écrit.

### 8.12 Ajouter un article
- **Manuel** : le menu de l'article, puis « Insérer un article après ». Saisir le titre (le crayon du titre), puis le contenu.
- **Automatisé** : `CreerModeleArticle(ide,bloc,n,'ARTICLE','AP')`. Saisir le **titre** par `modifier_titre_article`, puis le **contenu** dans une **deuxième** action, pour ne pas avoir les deux éditeurs ouverts. Vérifier ensuite que l'article est bien vide avant d'y écrire, car les numéros se décalent.

### 8.13 Aligner un modèle sur un dossier qui fonctionne
1. Relire le dossier de référence : les variables (nom, type, valeur ou formule), l'intitulé, tous les articles (titre et HTML), les attendus.
2. Relire le modèle de la même façon.
3. Présenter le différentiel : renommer, créer, supprimer, textes à remplacer, articles à insérer. **Préférer le renommage** à la suppression et recréation, pour garder l'identifiant.
4. Après accord, appliquer dans cet ordre : renommages, créations, **textes**, puis **suppressions** en dernier (rien ne doit encore les utiliser), et enfin l'ordre des variables.
5. Recharger, puis comparer automatiquement (noms, types, ordre, titres) et chercher les variables orphelines.

### 8.14 Créer, déposer, modifier un dossier de test Mes-Démarches
- Création et remplissage : section 5.
- **Dépôt** : « Déposer le dossier ». Le mode automatique peut le bloquer (« transaction réelle ») : demander l'approbation.
- **Modification après dépôt** : passer par `/dossiers/<dossier>/modifier`, puis **« Déposer les modifications »**. Sans ce dépôt, les annotations et Lexpol voient l'ancienne version.
- **Identité** : `/dossiers/<dossier>/identite`.

### 8.15 Créer ou mettre à jour l'acte Lexpol depuis Mes-Démarches
1. Dans les annotations privées, le lien « **Créer le dossier Lexpol** » (`a[href$="/lexpol/upsert"]`, c'est un lien et non un bouton). Attendre le NOR et le statut « En préparation ».
2. Ouvrir le dossier Lexpol, puis relever le « **Modèle utilisé** ».
3. « **Mettre à jour le dossier Lexpol** » ne renvoie que les valeurs. Si le NOR change, c'est qu'un nouveau dossier a été créé, probablement parce que le modèle configuré a changé.

### 8.16 Générer le PDF et le comparer au projet d'arrêté
0. **Demander d'abord** si l'utilisateur préfère générer et contrôler le PDF lui-même. C'est souvent le cas : il suffit alors de lui dire précisément ce qu'il doit lire, et le rendu attendu.
1. Cliquer sur « Voir le fichier », qui ouvre un onglet `geda_getFichier.php` (PDF).
2. Faire des captures de l'onglet PDF (une page par capture, en cliquant les vignettes), puis les relire.
3. Comparer au projet d'arrêté selon la grille de l'étape 6, et présenter les écarts dans un tableau.
4. Fermer l'onglet PDF.

---

## 9. Diagnostic : symptôme, cause probable, vérification

| Symptôme dans l'acte | Causes probables, par ordre de fréquence | Comment vérifier |
|---|---|---|
| `{@Variable@}` affichée telle quelle | 1. nom du texte ≠ nom de la variable (apostrophe ’/', accent, `(s)`, espace) · 2. variable supprimée ou renommée | liste des variables orphelines ; comparer les noms caractère par caractère |
| Variable vide | 1. Mes-Démarches envoie un **autre nom** (ex. `Demandeur nom` et non `nom`) · 2. le champ est **masqué** dans ce cas d'usage · 3. la donnée n'est **pas envoyée** du tout (vérifier en cherchant sa valeur dans la prévisualisation) · 4. acte créé **avant** la correction | « Prévisualiser les variables » du dossier |
| Une condition SI ne se déclenche jamais | 1. formule comparée à « Oui » au lieu de `true` · 2. variable source en Texte vide · 3. nom de la variable dans `SI_…` différent | ouvrir la formule ; « Vérifier la valeur calculée » dans un dossier qui a des valeurs |
| Ligne vide dans un tableau | balises SI dans la 1re et la dernière cellule | appliquer la section 4.3 |
| Paragraphe vide | même cause, avec des `<p>` | appliquer la section 4.3 |
| L'acte n'a pas les corrections du modèle | dossier Lexpol créé avant la correction | recréer l'acte |
| Variables inattendues (ancienne version) | l'acte a été créé depuis **un autre modèle** | « Modèle utilisé » dans Lexpol ; « Sélectionner un modèle Lexpol » dans le paramétrage du champ |
| Une donnée du registre Tahiti n'arrive pas | 1. nom de la variable Lexpol différent de `Numéro Tahiti – Entreprise …` (souvent un trait d'union « - » au lieu du tiret « – ») · 2. établissement non sélectionné dans le dossier · 3. acte créé avant le correctif | « Prévisualiser les variables » du dossier |
| Une autre donnée dérivée n'arrive pas | elle n'est pas déclarée dans « **Variables Lexpol** » | paramétrage du champ Lexpol ; ajouter la ligne `chemin = nom` (par l'utilisateur) |
| Dépôt impossible : « X doit être rempli » | case à cocher seule marquée obligatoire | rendre la case facultative |
| La modification d'un dossier n'apparaît pas | « Déposer les modifications » non cliqué | page `/modifier` |

---

## 10. Leçons du premier chantier (à ne pas répéter)

- **Lire la documentation fournie en entier, images comprises.** Une extraction de texte d'un PDF fait d'images n'avait livré que la syntaxe ET/OU/NON. `{@SINON@}`, `{@SI_NON_…@}`, les zones conditionnées et la case « donnée personnelle » étaient passés inaperçus.
- **Ne pas affirmer qu'une chose est impossible sur la seule foi de la documentation.** La variable de composition était « interdite » par le guide GEDA, et elle fonctionne. Proposer un test.
- **Ne jamais supposer le nom ni le format d'une variable envoyée** : lire la prévisualisation. Les hypothèses `civilite`, `prenom`, `nom` et « Oui » étaient toutes fausses.
- **Vérifier une absence en cherchant la valeur**, pas seulement le nom supposé, avant de conclure qu'une donnée n'est pas envoyée.
- **Consulter le paramétrage du champ Lexpol dès le début** (modèle sélectionné, zone « Variables Lexpol », variables disponibles). Faute de l'avoir fait, on a cherché pendant des heures d'où venait le modèle 631388 et pourquoi la raison sociale apparaissait. Tout était écrit là.
- **Signaler immédiatement les conséquences d'un réglage repéré.** La liste des champs montrait « Case à cocher (obligatoire) » et le blocage du dépôt n'a été vu qu'au dépôt.
- **Les apostrophes** : on les a corrigées deux fois. Imposer l'apostrophe droite dès le départ.
- **Tester d'abord dans un dossier, jamais directement dans le modèle**, et ne reporter que ce qui est validé.
- **Ne pas inventer de contenu métier** (options de listes, espèces, îles) : créer les champs, et laisser l'utilisateur remplir.
- **Après chaque lot d'actions dans Lexpol, recharger et relire l'état réel.** Les « absente » en cascade venaient d'un panneau rechargé, pas d'une réussite.
- **Un dossier Lexpol est une copie figée** : pour juger le modèle corrigé, recréer un acte.
- **Rester dans le périmètre de pages autorisé**, et ne pas rouvrir une page sans nécessité quand l'utilisateur y travaille.

---

## 11. Annexe : exemple de référence, le modèle 630543 (démarche 3558, au 21/10/2026)

Il fonctionne et sert de modèle type. Le dossier de test ZZZ26000726TT (idw 661657, cas personne morale résidente) en est une copie conforme, à deux variables inutilisées près (`designation demandeur debut phrase`, `raison sociale minuscules`, à supprimer).

**Typologie de ses 45 variables :**

| Famille | Variables | Type | Source |
|---|---|---|---|
| Champs texte, liste et date | `Nom du projet`, `Espèce(s) de …`, `Localisation des …`, `Début/Fin d'approche des …`, `Type de plongée` | Texte | libellé exact du champ Mes-Démarches |
| Données du registre | `Raison sociale`, `Nom commercial` | Texte | déclarées dans la zone « Variables Lexpol » du champ Lexpol (`Numéro Tahiti.etablissement.entreprise_raison_sociale = Raison sociale`…) ; `Raison sociale` est aussi le libellé d'un champ texte de la démarche *(depuis le correctif, ces déclarations ne sont plus indispensables : `Numéro Tahiti – Entreprise raison sociale` est envoyé d'office)* |
| Cases à cocher | `Baleines`, `Requins`, `Tortues`, `Dauphins`, `Crabes`, `A terre`, `Avec mise à l'eau`, `Drone` | **Vrai/Faux** (elles reçoivent `true`) | cases Mes-Démarches |
| Oui/Non | `Résident`, `Personne morale ?` | Texte (`true`/`false`) | champs Oui/Non |
| Titre de section | `Conditions d'approche` | Texte | résumé envoyé par Mes-Démarches |
| Identité | `Demandeur civilité`, `Demandeur prénom`, `Demandeur nom` | Texte | étape Identité |
| Calculées | `personne_morale_` = `{@Personne morale ?@}="true"` · `personne_physique_` = `NON({@Personne morale ?@}="true")` · `resident_` = `{@Résident@}="true"` | Vrai/Faux calculée | formules |
| Intermédiaire, **inutilisée** | `raison sociale minuscules` = `{@Raison sociale@:minuscules}` | Texte | plus référencée depuis le 21/10 : à supprimer |
| Composition | `demandeur milieu de phrase`, `demandeur debut de phrase` (section 4.2) | Texte | bloc conditionnel ; la seconde = la première avec `:prem_majuscule` |
| Anciennes, encore présentes | `demandeur`, `date_demande` | Texte | utilisées par l'attendu « Vu la demande de … » (hors périmètre) |

**Structure des textes :**
- **Intitulé** : `autorisant {@demandeur milieu de phrase@} à exercer…`
- **Article 1** : `{@demandeur debut de phrase@} est autorisé(e)…` (sans format dans le texte, section 4.1)
- **Article 2** : `{@Nom du projet@}`, puis un tableau Groupe / Espèces / Zones / Période, avec une **ligne conditionnelle par animal** (technique de la section 4.3).
- **Article 3** : `{@Conditions d'approche@}`, puis des paragraphes conditionnels (mise à l'eau, baleines, drone) avec les balises accolées.
- **Article « Modalités… des baleines »** : **condition d'article** `{@Baleines@} = Vrai` (zone conditionnée).
- **Article « Engagements »** : liste « 1° … ; » à « 6° … . », avec `{@NUM_ARRETE_BC@}`.

**Points restant à proposer** : marquer `Demandeur prénom` et `Demandeur nom` comme données personnelles ; l'attendu « Vu la demande de {@demandeur@} » (vide), qui relève de l'utilisateur.
