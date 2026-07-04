# Atelier publipostage v3 — Design

**Date** : 2026-07-03
**Statut** : validé (brainstorming avec Christian)

## Contexte et problème

PublipostageV3 (`app/lib/publipostage_v3.rb`, gem sablon) permet aux agents de rédiger
leurs modèles Word. La syntaxe sablon est puissante mais sujette à erreur pour un
utilisateur non technique. Frictions identifiées :

1. **Fichier de configuration YAML** requis (`champs:`, `modele`, `nom_fichier`) —
   rédigé par Christian, redondant avec le contenu du template.
2. **Syntaxe couplée à la démarche** : noms de champs à parameterizer, `present?` sur
   les booléens, `.image` sur les images, boucles `each/endEach` pour les répétitions.
3. **Itérations de test pénibles** : il faut modifier un dossier réel pour déclencher
   une génération.

### Contrainte technique clé (vérifiée)

Sablon 0.4.3 ne reconnaît **que de vrais champs de fusion Word** (`fldSimple` /
`fldChar` + `instrText` avec `MERGEFIELD nom \* MERGEFORMAT` —
cf. `Sablon::Parser::MailMerge::KEY_PATTERN`). Le `«=champ»` visible dans les templates
n'est que l'affichage d'un merge field : du texte brut collé dans Word est invisible
pour sablon. Un copier-coller texte depuis une page web ne peut donc pas fonctionner.

### Contrainte de régénération

Le contexte envoyé à sablon ne doit contenir **que les champs réellement utilisés par
le template** : si tous les champs du dossier étaient injectés, le checksum de
déclenchement provoquerait une régénération à chaque modification de n'importe quel
champ, même hors périmètre du document.

## Décisions actées

| Décision | Choix | Alternatives écartées |
|---|---|---|
| Public cible | L'agent final, en autonomie, via une page web admin | CLI/rake réservé à Christian |
| Copier-coller des champs | **Option A : palette .docx** avec merge fields natifs, copie Word→Word | Option B (pré-processeur texte brut « … » → merge fields) : trop risquée à cause du découpage en *runs* par Word ; Option C (clipboard RTF) : fragile |
| Extraction des besoins | **Niveau 2 : production aussi** — PublipostageV3 dérive sa liste de champs du template | Niveau 1 (extraction limitée au banc d'essai) |
| Unicité des noms | Noms canoniques générés par un algorithme partagé palette ↔ extracteur, désambiguïsation déterministe | Mapping inverse heuristique |
| Dossier de test | Dossier **réel** (plus sûr, facile à créer) | Dossier factice synthétisé |
| Contrôle d'accès | Bearer de l'app ; si démarche inaccessible → message « ajoutez clautier@idt.pf comme administrateur » | Token admin fourni par l'agent : rejeté (notion inconnue des agents, token visible à la création uniquement → fuite en clair sur les PC) |
| Déploiement du template | **Hors périmètre** — reste manuel (circuit staging/prod). Un futur déploiement se fera directement dans Mes-Démarches | Publication depuis l'Atelier |

## Architecture — six briques

### 1. Dictionnaire canonique (fondation)

Module partagé qui, à partir du descripteur GraphQL d'une démarche, construit
`{nom_canonique → descripteur de champ}` :

- parcours des champs **et annotations** (+ sous-champs des répétitions) ;
- `parameterize(separator: '_')` sur chaque libellé (cohérent avec
  `normalize_context`) ;
- collisions désambiguïsées de façon **déterministe** (suffixe `_2`, `_3`… dans
  l'ordre du descripteur) — traite aussi les libellés homonymes (deux « Commentaire »
  dans deux sections).

Source de vérité unique utilisée par la palette, l'extracteur, le linter et la
construction du contexte de génération. Même algorithme partout ⇒ mapping inverse
fiable par construction (simple lookup).

### 2. Générateur de palette .docx

Pour une démarche, produit un document Word téléchargeable : une entrée par champ
avec libellé, type, et le **merge field natif** prêt à copier
(`<w:fldSimple w:instr=" MERGEFIELD nom \* MERGEFORMAT ">`). L'agent ouvre la palette
à côté de son modèle et copie-colle **dans Word** — la copie Word→Word préserve les
champs de fusion.

Snippets par type :

- texte/nombre/date → `«=nom_du_champ»` ;
- booléen (Checkbox/YesNo) → `«=nom»` (Oui/Non) et bloc
  `«nom:if(present?)»…«nom:endIf»` ;
- pièce justificative → boucle complète avec triplet image
  (`«pjs:each(f)»«@f.image:start»[img]«@f.image:end»«pjs:endEach»`) et variantes
  métadonnées (`nom`, `taille`, `lien`, `type`) ;
- répétition → `«bloc:each(item)»…«bloc:endEach»` avec toutes les colonnes
  `«=item.colonne»` pré-écrites ;
- référentiel de Polynésie → valeur principale + colonnes `«=champ.colonne»`.

Implémentation : rubyzip + gabarit `document.xml` (ERB ou construction Nokogiri).
Aucune nouvelle gem. La palette sert aussi d'antisèche imprimable.

### 3. Extracteur de besoins

Parse un .docx (corps **+ en-têtes/pieds de page**) en réutilisant
`Sablon::Parser::MailMerge` pour lister les expressions, puis en déduit l'ensemble
des champs racine requis :

- `=nom`, `nom:each(x)`, `nom:if(…)`, `@x.image` ;
- les variables de boucle (`x` dans `each(x)`) sont exclues des besoins ;
- sortie : ensemble de noms canoniques.

### 4. Linter

Croise les expressions extraites avec le dictionnaire. Erreurs bloquantes :

- nom inconnu (avec suggestion du nom canonique le plus proche) ;
- `each`/`endEach` et `if`/`endIf` non appariés ;
- variable de boucle utilisée hors de sa boucle ;
- PJ utilisée sans `.image` ni métadonnée ; booléen mal employé.

**Avertissement non bloquant** : nom inconnu pouvant correspondre à une valeur
calculée (`calculs:`) — le sujet calculs reste ouvert, on ne le bloque pas.
Rapport en français, actionnable.

### 5. Évolution de PublipostageV3 en production

- `champs:` devient **optionnel** : absent, la liste est dérivée de l'extraction du
  template (cache par checksum du template) ;
- le checksum de régénération ne porte que sur les champs extraits ;
- **rétrocompatible** : un YAML avec `champs:` explicite garde le comportement
  actuel ;
- YAML minimal : `modele` + `nom_fichier` + état déclencheur (+ `calculs` éventuels).

Conséquence assumée : le template devient une source de config vivante (modifier le
.docx change le périmètre de régénération).

### 6. Page admin « Atelier publipostage »

Sur le modèle de `admin/schema_builder`. Parcours :

1. l'agent saisit le **numéro de démarche** ; le serveur vérifie l'accès avec le
   bearer de l'app (`GRAPHQL_BEARER`). Si inaccessible → message :
   « demandez à ajouter clautier@idt.pf comme administrateur de la démarche » ;
2. **télécharger la palette** de champs (.docx) ;
3. **uploader son modèle** .docx → rapport de lint immédiat ;
4. saisir un **numéro de dossier réel** → génération d'essai (contexte construit
   depuis l'extraction, court-circuite entièrement le YAML) → téléchargement du
   document généré.

Aucune publication vers la production depuis la page. Aucun token manipulé par
l'agent.

## Hors périmètre

- Déploiement/publication du template (manuel via circuit staging/prod ; à terme,
  intégré directement dans Mes-Démarches) ;
- résolution des `calculs:` dans le banc d'essai (avertissement seulement) ;
- option B (pré-processeur texte brut « … » → merge fields) ;
- dossier factice synthétisé depuis le schéma.

## Tests

- **Dictionnaire** : collisions/désambiguïsation, accents, annotations, sous-champs
  de répétition ;
- **Palette** : XML des `fldSimple` valide (relisible par
  `Sablon::Parser::MailMerge`), blocs complexes complets par type ;
- **Extracteur** : expressions imbriquées, exclusion des variables de boucle,
  en-têtes/pieds de page ;
- **Linter** : chaque règle, suggestions, avertissement calculs ;
- **Production** : génération sans `champs:` (rétrocompatibilité + checksum
  restreint aux champs extraits) ;
- **Request spec** de la page (accès refusé, palette, lint, génération d'essai).

## Risques et points ouverts

- **Calculs** : les valeurs calculées ne sont pas dans le dictionnaire ; un template
  qui en utilise passe le lint avec avertissement mais la génération d'essai rendra
  ces champs vides. À traiter dans un chantier ultérieur.
- **Stabilité des noms canoniques** : renommer un champ dans la démarche casse le
  template silencieusement en prod — le linter de l'Atelier permet de re-vérifier un
  template après évolution de la démarche.
- **Fragmentation Word** : sans objet pour les merge fields natifs (raison du choix
  de l'option A).
