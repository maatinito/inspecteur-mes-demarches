# Importation de poussins d'un jour (DBS / cellule zoosanitaire) — Architecture & devis

- **Date** : 2026-08-18
- **Service** : Direction de la biosécurité (DBS), cellule zoosanitaire
- **Démarches** : 3 à créer (aucune n'existe aujourd'hui)
- **Sources** : `docs/dbs/import_volaille/` — `Partie importateur.pdf`, `Partie Eleveur.pdf`, `Suivi de quarantaine.pdf` (formulaires papier annotés par le service)
- **Objet** : cadrer l'architecture **avant** de créer les formulaires, et produire un **devis de charge de développement**.

---

## 1. Principe directeur

**Le parcours est une cascade d'invitations préremplies, pilotée par un référentiel.**

L'importateur est l'initiateur : il déclare son lot et joint le classeur de ses éleveurs destinataires.
Chaque éleveur valorisé reçoit un courriel contenant deux liens de préremplissage — son engagement et son
carnet de suivi. Le robot n'attend jamais personne : la cascade est **non bloquante**, et c'est le
référentiel qui porte la mémoire de qui a été invité, qui a répondu, et qui se tait.

### Le point dur, et sa résolution

Le vétérinaire exige que **toutes les cases du relevé de mortalité soient remplies**. Trois contraintes
s'opposaient :

1. l'obligation d'un champ ne s'applique qu'au **dépôt** ;
2. un dossier en **brouillon** est invisible de l'administration — donc **aussi du robot** : pas de relance,
   pas d'alerte, aucune visibilité pendant 21 jours ;
3. déposer dès le premier jour un relevé encore vide n'a pas de sens pour l'usager.

La résolution tient en trois mouvements :

- **Le dépôt à J0 est renommé.** Ce n'est pas un relevé prématuré, c'est l'**accusé de réception du lot**
  (« je confirme avoir reçu N poussins le JJ/MM »). Il a une valeur métier propre que la DBS n'a pas
  aujourd'hui : la confirmation que les poussins sont arrivés à destination.
- **Les 21 champs sont masqués par condition** sur un champ formule « Jour de suivi »
  (`aujourd'hui − date d'arrivage`), recalculé chaque nuit par la plateforme. Un champ masqué n'est pas
  exigé au dépôt : on peut donc les déclarer **obligatoires** sans empêcher le dépôt à J0. Ils deviennent
  exigibles au fil des jours.
- **La progressivité de secours appartient au robot.** Si la validation des champs obligatoires ne
  s'applique pas à l'enregistrement d'un dossier *en construction*, le robot n'exige que les **jours
  échus** et relance. Le calcul est de son côté, il ne dépend d'aucune capacité de la plateforme.

> **L'obligation native garantit que les cases sont pleines, pas qu'elles sont vraies.** Un éleveur bloqué
> au dépôt à J21 saisira vingt-et-un zéros en trente secondes. La relance après quatre jours de silence,
> elle, force la tenue réelle du journal. C'est le carnet quotidien — pas le blocage — qui sert le besoin
> réel du vétérinaire.

---

## 2. Flux fonctionnel

```
IMPORTATEUR : demande de laissez-passer + classeur des éleveurs
   │
   ▼  passage en_instruction par la DBS  ──►  déclencheur de la cascade
   │
   ├─► excel_vers_grist : tout le classeur → table Attributions (liée au dossier)
   │
   └─► un courriel par ligne VALORISÉE, deux liens préremplis :
          1. « Signer mon engagement »        → démarche ENGAGEMENT
          2. « Ouvrir mon carnet de suivi »   → démarche CARNET
       (date d'envoi horodatée dans Attributions → invitation traçable, non rejouable)

ÉLEVEUR / ENGAGEMENT                     ÉLEVEUR / CARNET
   dépôt = signature                        dépôt J0 = accusé de réception du lot
   saisit son n° Tahiti  ──────────────►    puis relevé quotidien, en construction
   ▼                                        ▼
   certificat d'isolement (publipostage)    J+4 sans saisie → relance
                                            seuil de mortalité franchi → ALERTE zoosanitaire
                                            J21 → relance de complétude
                                            ▼
                                            visite vétérinaire : compte rendu en annotations
                                            ▼
                                            suite administrative (levée / prolongation / abattage)

DBS : délivrance du laissez-passer (publipostage) + information des services par courriel
```

**La cascade est non bloquante** : le laissez-passer est délivré même si des engagements manquent. Les
éleveurs silencieux sont régularisés par relance, et remontés au vétérinaire par le tableau de bord.

---

## 3. Les trois démarches

### 3.1 Demande de laissez-passer — importateur

Les champs *barrés* du formulaire papier (nom du responsable, prénom, adresse géographique, courriel) le
sont parce que Mes-Démarches les connaît déjà par le compte du déposant — **à confirmer avec le service**.
Les champs *ajoutés* par le service sont le n° Tahiti et le n° de permis d'importation préalable.

**Champs usager** : entreprise, n° Tahiti, BP / code postal / ville, Vini, n° de permis d'importation,
date d'arrivée, pays de provenance, moyen de transport, n° de vol, n° de LTA, expéditeur, date et n° du
certificat sanitaire, effectif total, ponte ou chair, race, déclarant en douane, nombre de colis,
**classeur des destinataires**.

> Le certificat sanitaire et le déclarant en douane ne figurent pas sur le formulaire papier, mais le
> laissez-passer et le certificat d'isolement les exigent tous les deux. Sans collecte en amont, le
> vétérinaire les ressaisit à la main.

**Annotations privées** : visa de l'agent habilité, date de délivrance.

### 3.2 Engagement de l'éleveur

**Préremplis par URL** : n° du dossier importateur (champ lien dossier), nom de l'élevage, courriel,
effectif attribué, date d'arrivage, vol.

**Saisis par l'éleveur** : nom de l'éleveur, **n° Tahiti**, adresse et commune du lieu d'isolement,
téléphone, et la case obligatoire « j'ai lu et j'approuve les sept engagements ».

Le dépôt vaut signature — horodatage et identité du compte. C'est le standard de la plateforme, mais
l'article 7 de l'arrêté n° 171 CM du 1er mars 2006 fait peser sur l'éleveur l'abattage total du lot à ses
frais exclusifs sans indemnisation : **une validation juridique explicite du service est requise**.

**Annotations privées** : date du certificat d'isolement, date de levée prévue (formule : arrivage + 21 j),
visa de l'agent.

C'est cette démarche qui produit le **certificat d'isolement**, nominatif par élevage.

### 3.3 Carnet de suivi

**Préremplis par URL** : n° du dossier importateur, nom de l'élevage, courriel, effectif attribué,
date d'arrivage.

**Champs usager** :
- en-tête d'accusé de réception (confirmation de l'effectif reçu et de la date) — seuls champs visibles à J0 ;
- champ formule **« Jour de suivi »**, placé **avant** les champs conditionnés (contrainte de l'API de
  condition : le champ source doit précéder le champ conditionné) ;
- **21 champs nombre obligatoires**, chacun conditionné par `Jour de suivi >= N` ;
- bloc répétable **« jours supplémentaires »** pour les prolongations d'isolement ;
- deux formules : total de mortalité, effectif restant.

**Annotations privées — le compte rendu de visite** (page 2 du document de suivi) : date de visite, agents,
bloc répétable vaccins et traitements, niveau d'activité, alimentation, signes cliniques, autre,
prolongation oui/non avec durée et date de prochaine visite. Plus le n° de dossier de l'engagement, posé
par le robot au dépôt de celui-ci.

**Cycle de vie** : l'éleveur ne « termine » jamais son dossier, il le tient. C'est le vétérinaire qui passe
en instruction après sa visite de levée, saisit son compte rendu, et accepte.

### 3.4 Le classeur

Six colonnes, en-tête en ligne 1, une feuille nommée : nom de l'élevage, nom de l'éleveur, courriel,
commune ou île, n° Tahiti *facultatif*, quantité attribuée.

**Règle de lecture** : le classeur est recopié **intégralement**, y compris les lignes sans quantité —
conformément au contrat « copieur, pas correcteur » de `excel_vers_grist`. Le filtre « quantité
renseignée » est une **condition d'envoi** côté robot et une **formule** côté Grist, pas une règle de
lecture du fichier.

> Ce choix suit l'usage réel décrit par le service : l'importateur conserve d'une fois sur l'autre le
> fichier de **tous** ses éleveurs et ne renseigne que la colonne des quantités du voyage. Bénéfice
> secondaire : l'annuaire personnel complet remonte dans le référentiel, y compris les éleveurs non
> destinataires ce voyage-ci.

---

## 4. Modèle de données (Grist)

**Contrainte structurante : la synchro traduit une démarche en une table, clée par le numéro de dossier.**
Elle ne sait pas produire une table dont la clé serait composite.

| Table | Origine | Clé |
|---|---|---|
| `Lots` | miroir de la démarche importateur | n° dossier importateur |
| `Attributions` | **`excel_vers_grist`** — table *liée* au dossier importateur | `(Dossier, Ligne)` du classeur |
| `Engagements` | miroir de la démarche engagement | n° dossier engagement |
| `Carnets` | miroir de la démarche carnet | n° dossier carnet |
| `Elevages` | annuaire, alimenté par `Attributions` + `Engagements` | courriel normalisé |

`Engagements` et `Carnets` portent une colonne `Lot` en `Ref` vers `Lots`, alimentée depuis le champ
lien-dossier prérempli.

> **Piège connu** : écrire une clé métier directement dans une colonne `Ref` ne produit **rien**, sans
> erreur. Il faut l'encodage liste `["l", numero_dossier]`. Filtrer par la clé métier ne matche pas non
> plus.

### Rattachement et doublons

L'identifiant d'une attribution est la **paire (n° dossier importateur, courriel de l'éleveur)** — tous deux
préremplis. Aucun jeton d'invitation spécifique n'est créé : le numéro de dossier est la référence
naturelle, il est vérifiable, `DossierLinkCheck` sait contrôler qu'il pointe vers la bonne démarche, et
Mes-Démarches le rend cliquable.

Si l'éleveur **modifie** le courriel prérempli, le rattachement au lot tient mais l'élevage ne se retrouve
pas : le robot signale l'anomalie à l'agent. C'est le cas qu'on veut voir remonter, pas une panne
silencieuse.

Si l'éleveur ouvre **deux carnets**, la synchro crée deux lignes — et c'est correct, le miroir doit rester
fidèle. Le rapprochement se fait par formule sur `(Lot, courriel)`, et deux carnets rattachés à la même
attribution deviennent un compteur visible. Le signal « cet éleveur a deux journaux, lequel fait foi ? »
est mis sous les yeux du vétérinaire plutôt que résolu en silence par le robot.

### Les trois rôles du référentiel

1. **Trace des invitations** — le seul endroit du système qui sache **qui a été invité et n'a rien fait**.
   Un éleveur qui n'a jamais cliqué n'a aucun dossier : il est invisible partout ailleurs.
2. **Tableau de bord du vétérinaire** — isolements en cours, engagements signés, carnets ouverts, mortalité
   cumulée, dates de levée prévues. C'est son point d'entrée quotidien, **pas** la liste des dossiers MD,
   qui comptera des dizaines de dossiers en construction par lot.
3. **Annuaire des élevages** qui se constitue import après import, sans saisie dédiée, et **canal de
   diffusion inter-services** en remplacement des copies papier.

Le n° Tahiti et le lieu d'isolement arrivent **par l'aval** : c'est l'éleveur qui les saisit en signant son
engagement, il est le seul à les connaître avec certitude. L'importateur ne fournit que nom et courriel,
et n'est jamais bloqué sur une donnée qu'il n'a pas.

---

## 5. Cascade, relances et alerte

**Déclencheur** : passage en instruction du dossier importateur — un humain a vu la liste avant que des
dizaines de courriels partent, et le classeur est figé.

**Envoi** : un seul courriel par ligne valorisée, deux liens préremplis. La date d'envoi est écrite dans
`Attributions` : c'est elle qui rend l'invitation traçable et non rejouable.

**Quatre relances** :

| Relance | Déclenchement | Destinataire |
|---|---|---|
| Engagement non signé | quelques jours après l'invitation, puis à l'arrivée du lot | éleveur |
| Carnet non ouvert | pas d'accusé de réception du lot | éleveur **et vétérinaire** |
| Silence de 4 jours | carnet ouvert mais non tenu | éleveur |
| J21 | complétude du relevé, puis « lot mûr pour la visite de levée » | éleveur, puis vétérinaire |

**Une alerte**, distincte des relances : franchissement du seuil de mortalité, adressée à la cellule
zoosanitaire **le jour même**.

> L'engagement n° 2 impose de signaler immédiatement toute mortalité anormale, ce qui repose aujourd'hui
> entièrement sur l'initiative de l'éleveur. Le carnet quotidien rend la donnée lisible par le robot le
> jour même : un lot qui perd trente pour cent de son effectif à J4 est aujourd'hui découvert trois
> semaines plus tard, ou jamais. Gain de biosécurité réel, pour un coût marginal — le seuil est une règle
> de configuration. **Sa valeur doit être fixée par le vétérinaire.**

**Contrainte de mise en œuvre** : le curseur `checked_at` est partagé par démarche. Les relances de la
démarche carnet doivent être des tâches du **bloc existant**, pas un second bloc, sinon elles seraient
affamées.

---

## 6. Documents produits

Trois gabarits en publipostage v3 :

| Gabarit | Démarche | Portée |
|---|---|---|
| `laissez-passer.docx` | importateur | un par lot, à la délivrance |
| `certificat-isolement.docx` | engagement | un par éleveur, nominatif |
| `suite-administrative.docx` | carnet | un par éleveur, à la levée ou à la prolongation |

> La page « suites administratives » n'est pas une annexe pré-imprimée à remplir à la main : c'est le
> **document de décision de fin de parcours** (levée, prolongation avec motif, abattage). La décision se
> prend dans le carnet, à partir du compte rendu de visite — le document doit donc en être publiposté.

### Numérotation : aucune

**Le numéro de dossier Mes-Démarches est la référence unique.** Pas de chrono maison, conformément à
l'usage établi avec ce service sur les dossiers précédents. Cela supprime le numéroteur séquentiel, la
série d'accusés de réception, la question des séries partagées avec les autres circuits zoosanitaires et
la reprise des compteurs en cours.

Bénéfice de cohérence : le certificat d'isolement porte le numéro du dossier d'engagement, qui est aussi la
clé de sa ligne dans `Engagements`, qui est aussi ce que le champ lien-dossier rend cliquable. **Une seule
clé, du document papier jusqu'à la table Grist.** Reste à fixer avec le service la *forme* de la référence
dans les gabarits. Le permis d'importation préalable reste saisi tant qu'il n'est pas dématérialisé.

### Signataire

Résolu par un mécanisme existant : **visa nominatif** posé dans le dossier, puis `calculs/email_to_names`
côté robot pour traduire l'identifiant en prénom, nom et fonction. La table des agents de la cellule
zoosanitaire est déjà écrite dans `dbs_laissez-passer.yml` derrière une ancre YAML réutilisable ; il
manque la ligne de la vétérinaire officielle actuelle. Le visa fait double emploi utile : il matérialise
aussi l'acte de délivrance.

*(Une table Baserow globale des agents par service serait une bonne généralisation, mais le besoin n'est
pas posé — hors périmètre.)*

### Diffusion

Les copies papier (MPR, DBS, DDI, DAG, DGAE, destinataire) deviennent **un courriel d'information** —
le moteur ne sait pas transférer de pièce jointe aujourd'hui — **plus une vue Grist consultable à la
demande**. La pièce jointe est jugée lourde et inadaptée à une diffusion d'information ; le référentiel
est le bon support d'accès. **La liste de diffusion électronique reste à obtenir du service.**

### Pièges du publipostage

- **Seuls de vrais MERGEFIELD Word sont remplacés** : un `«champ»` tapé au clavier ressort tel quel, sans
  erreur. Les gabarits seront construits à partir de l'annexe produite par `bin/generer_annexe`.
- **Les clés sont normalisées**, d'où des collisions entre un champ et une annotation aux libellés proches
  à la casse ou aux accents près. Risque concret ici : « Nombre de poussins » existe côté importateur,
  côté certificat d'isolement et côté carnet. **Libellés distincts à fixer dès la conception.**
- **Tableau des articles réglementés** du laissez-passer : une seule ligne en pratique (poussins de ponte
  ou de chair, code NC 010511, *Gallus gallus*), donc pas de boucle. Si un lot peut mélanger ponte et chair
  ou plusieurs races, il en faut une — capacité à vérifier sur v3.

---

## 7. Décisions tranchées

| # | Décision | Alternative écartée |
|---|---|---|
| 1 | Trois démarches neuves | Greffe sur un existant : aucune démarche poussins n'existe |
| 2 | Classeur joint côté importateur | Bloc répétable : plusieurs dizaines d'éleveurs par import, l'importateur a déjà son fichier |
| 3 | Cascade **non bloquante** | Blocage du laissez-passer sur les engagements : un éleveur silencieux immobiliserait tout le lot |
| 4 | Déclenchement au passage en instruction | Au dépôt (courriels partis avant toute vérification) ; sur clic agent (geste manuel, risque d'oubli) |
| 5 | Carnet ouvert dès J0, relance J21 pour compléter | Création à J21 : saisie rétroactive de 21 jours de mémoire |
| 6 | **Dossier déposé dès J0**, en construction | Brouillon 21 jours : invisible du robot, ni relance ni alerte possibles |
| 7 | 21 champs obligatoires masqués par condition | Bloc répétable (case vide = ligne absente, complétude non garantie) ; classeur côté éleveur (tableur non garanti) |
| 8 | Référentiel clé courriel, n° Tahiti par l'aval | Référentiel en *entrée* : ressaisie imposée à l'importateur |
| 9 | Numéro de dossier comme référence unique | Chrono maison par série et par millésime |
| 10 | Copies = courriel d'information + accès Grist | Envoi de pièces jointes : non supporté, et inadapté à une diffusion |

---

## 8. Réserves et questions ouvertes

**Réserves à lever pendant le projet**

1. **Validation juridique** de la case « lu et approuvé » comme signature de l'engagement, au regard de
   l'article 7 (abattage total aux frais de l'éleveur, sans indemnisation).
2. **Validation des champs obligatoires à l'enregistrement** d'un dossier en construction — si elle ne
   s'applique pas, la progressivité côté robot prend le relais (déjà chiffrée).
3. **Seuil de mortalité** déclenchant l'alerte : à fixer par le vétérinaire.

**Questions au service**

- Forme exacte de la référence documentaire dans les gabarits.
- Liste de diffusion électronique des laissez-passer.
- Confirmation que les champs barrés du formulaire importateur le sont parce que Mes-Démarches connaît le
  déposant.
- Un lot peut-il mélanger ponte et chair, ou plusieurs races ? (conditionne une boucle de tableau)

**Dépendance de planning**

`excel_vers_grist` porte le poste `Attributions`. Le moteur est **écrit, testé et commité**
(`app/lib/excel_vers_grist.rb`, specs associées) et **déployé en staging** sur le cas pesticides
(`dbs_pesticides_grist.yml`). Il n'est **pas encore en production** : le workflow n8n de référence tourne
toujours, et la phase 3 du plan — validation live puis décommissionnement de n8n — reste à conduire.

Conséquence favorable : le poste `Attributions` relève de la **configuration**, pas du développement, et
s'appuiera sur un moteur déjà éprouvé en conditions réelles. Deux points de vigilance seulement : la
validation pesticides doit être acquise avant qu'un second service en dépende, et le déclencheur diffère
(`accepte` chez pesticides, `en_instruction` ici) — c'est un paramètre, pas une évolution.

**Piste hors périmètre**

Rendre cliquable une annotation privée de type lien dossier dans Mes-Démarches. Aujourd'hui le champ est en
mode édition et n'offre aucun lien de navigation, ce qui prive l'agent du chaînage carnet → engagement posé
par le robot.

---

## 9. Devis

| Poste | Contenu | Charge |
|---|---|---|
| Conception des trois démarches | Champs, annotations, formule « Jour de suivi », 21 conditions d'affichage, blocs répétables, modèle de classeur | 3 j |
| Cascade d'invitation | Construction des URL de préremplissage, envoi par ligne valorisée, idempotence, horodatage dans Grist | 3,5 j |
| Référentiel Grist | Trois tables miroir, `Attributions` par le classeur, table `Elevages`, formules de rapprochement, tableau de bord | 3 j |
| Contrôles et relances | Complétude progressive sur jours échus, quatre relances, alerte mortalité, signalement des muets | 3 j |
| Documents | Trois gabarits, annexes de fusion, visas, courriels d'information aux services | 3,5 j |
| Recette et déploiement | Lot fictif bout en bout sur staging, accompagnement du service, mise en production | 4 j |
| | **Total** | **≈ 20 j** |

**Postes supprimés en cours de cadrage** (documentés pour mémoire) : numéroteur séquentiel réglementaire,
client REST de préremplissage — l'URL `?ChampId=Valeur` suffit — et gestion du nom du signataire dans les
gabarits, déjà couverte par le visa et `email_to_names`.

**Option non chiffrée** : table Baserow globale des agents par service (généralisation de
`email_to_names`), besoin non posé.
