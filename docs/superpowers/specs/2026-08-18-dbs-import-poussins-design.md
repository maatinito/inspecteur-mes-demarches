# Importation de poussins d'un jour (DBS / cellule zoosanitaire) — Architecture & devis

- **Date** : 2026-08-18 — **mis à jour le 2026-09-11** après réunion avec le service (voir §10)
- **Service** : Direction de la biosécurité (DBS), cellule zoosanitaire
- **Démarches** : 3 à créer — **un prototype de la démarche importateur existe : n° 3899** « Demande de
  laissez-passer pour volailles d'un jour - TIM » (révision brouillon, non publiée), à reprendre ; analyse
  critique en §11
- **Sources** : `docs/dbs/import_volaille/` — `Partie importateur.pdf`, `Partie Eleveur.pdf`, `Suivi de quarantaine.pdf` (formulaires papier annotés par le service) ; depuis le 11/09 : les modèles Word vierges `Laissez passer vierge à compléter.docx`, `Certificat d'isolement poussin d'un jour et suite administrative  doc vierge .docx`, `Formulaire d'engagement poussins d'un jour à compléter.docx` et la `Fiche de suivi.xlsx` (J0 à J21)
- **Objet** : cadrer l'architecture **avant** de créer les formulaires, et produire un **devis de charge de développement**.

---

## 1. Principe directeur

**Le parcours est une cascade d'invitations préremplies, pilotée par un référentiel.**

L'importateur est l'initiateur : il déclare son lot et joint le classeur de ses éleveurs destinataires.
Chaque éleveur valorisé reçoit **deux invitations préremplies, à deux moments distincts** : le lien vers son
engagement dès le passage en instruction (il doit être signé *avant* l'arrivée des poussins), puis le lien
vers son carnet de suivi au visa du laissez-passer, quand le lot est là. Le robot n'attend jamais personne : la cascade est **non bloquante**, et c'est le
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
   ▼  en_instruction + case « Envoyer les engagements » cochée par l'agent  ──►  déclencheur n° 1
   │
   ├─► excel_vers_grist : tout le classeur → table Attributions (liée au dossier)
   │
   ├─► courriel n° 1 par ligne VALORISÉE : « Signer mon engagement » → démarche ENGAGEMENT
   │   (date d'envoi horodatée dans Attributions → invitation traçable, non rejouable)
   │
   └─► ORDRE DE PAIEMENT (payzen/payment_order) : lien PayZen à l'importateur, 5 jours
       (dès le DÉPÔT sans correspondance vers une île ; sinon à la saisie du
       « Créneau d'intervention retenu » par le vétérinaire)
       payé → « Paiement : Payé » ; expiré → relance + alerte agent (pas de classement : le lot arrive)

ÉLEVEUR / ENGAGEMENT
   dépôt = signature, saisit son n° Tahiti et le lieu d'isolement
   (à faire AVANT l'arrivée des poussins ; relance si silence)

DBS : VISA du laissez-passer par l'agent  ──►  déclencheur n° 2 (le lot arrive)
   │   (le robot ne publiposte le laissez-passer que si « Statut du paiement » ∈ {Payé, Gratuit})
   │
   ├─► publipostage du laissez-passer + courriel d'information des services
   ├─► publipostage du CERTIFICAT D'ISOLEMENT de chaque engagement signé
   │   (un engagement signé après le visa reçoit le sien à son dépôt)
   └─► courriel n° 2 par ligne valorisée : « Ouvrir mon carnet de suivi » → démarche CARNET
       J0 = date de clôture du laissez-passer

ÉLEVEUR / CARNET
   dépôt J0 = accusé de réception du lot, puis relevé quotidien, en construction
   ▼
   J+4 sans saisie → relance
   morts du jour ≥ 3 % de l'effectif restant la veille → ALERTE zoosanitaire le jour même
   J21 → relance de complétude, puis « lot mûr » au vétérinaire
   ▼
   visite vétérinaire : compte rendu en annotations
   ▼
   suite administrative (levée / prolongation / abattage)
```

**La cascade est non bloquante** : le laissez-passer est délivré même si des engagements manquent. Les
éleveurs silencieux sont régularisés par relance, et remontés au vétérinaire par le tableau de bord.

---

## 3. Les trois démarches

### 3.1 Demande de laissez-passer — importateur

> **Prototype existant : démarche 3899**, clonée du laissez-passer animaux de compagnie (2439). Elle sert de
> base mais plusieurs points sont à corriger avant publication — voir l'analyse critique en **§11**. Les
> `stable_id` cités ci-dessous et en §11 sont ceux de sa révision brouillon au 14/09/2026.

Les champs *barrés* du formulaire papier (nom du responsable, prénom, adresse géographique, courriel) le
sont parce que Mes-Démarches les connaît déjà par le compte du déposant — **à confirmer avec le service**.
Les champs *ajoutés* par le service sont le n° Tahiti et le n° de permis d'importation préalable.

**Champs usager** : entreprise, n° Tahiti, BP / code postal / ville, Vini, n° de permis d'importation,
date d'arrivée, pays de provenance, moyen de transport, n° de vol, n° de LTA, expéditeur, date et n° du
certificat sanitaire, effectif total, **ponte ou chair (un seul type par dossier — un importateur qui reçoit
les deux dépose deux dossiers, réponse du service du 11/09)**, race, déclarant en douane, nombre de colis,
**classeur des destinataires**.

> Le certificat sanitaire et le déclarant en douane ne figurent pas sur le formulaire papier, mais le
> laissez-passer et le certificat d'isolement les exigent tous les deux.
>
> **Retour du service (17/09) : la LTA et le certificat sanitaire arrivent tard**, souvent après le dépôt, et
> leurs références saisies par l'usager sont **souvent erronées** (dossiers dupliqués d'un import à l'autre).
> Décision : l'usager peut **joindre** les deux documents s'il les a, en **facultatif**, sous un titre qui
> explique qu'à défaut ils sont à envoyer dans la messagerie **au moins 24 h avant l'arrivée de l'avion** ;
> les **données** qui en sont tirées (n° de LTA, nombre de colis, n° et date du certificat, vétérinaire
> officiel signataire) ne sont **plus demandées à l'usager** : c'est **l'agent qui les renseigne en annotations
> privées**, et le publipostage les lit là. Le déclarant en douane reste un champ usager.

**Annotations privées** : « Importateur » (dénomination exacte du PIP, forçage), **données de la LTA et du
certificat sanitaire** (n° de LTA, nombre de colis, n° et date du certificat, vétérinaire officiel signataire —
renseignées par l'agent, 17/09), zones « Engagements reçus » / « Engagements manquants » (§3.2), **créneau
d'intervention retenu** par le vétérinaire (§3.5), visa de l'agent habilité, date de délivrance, et le bloc
**Paiement** (§3.5). Les listes de contrôle héritées du laissez-passer chats et chiens (« Demande d'avis
vétérinaire », « Informations à vérifier ») sont **supprimées** : les vérifications sont simples ici ; à
remettre si le service le demande.

### 3.2 Engagement de l'éleveur

> **Démarche créée : n° 4038** « Engagements pour recevoir des poussins d'un jour » (coquille dupliquée par
> l'utilisateur, champs construits par MCP le 21/09/2026). Identifiants ci-dessous ; la présentation
> (logo, instructeurs, messages) est réglée par l'utilisateur.

**La démarche est déclarée « personne morale »** (21/09) : le bloc d'identité de Mes-Démarches demande le
**n° Tahiti**, et l'entreprise qui en découle **est** le nom de l'exploitation — la question « nom de
l'élevage » est réglée sans champ dédié. Le **courriel est celui du compte** de connexion, il n'est pas
redemandé : le robot le lit sur le dossier, c'est aussi lui qui sert au rapprochement avec l'attribution (§4).

**Préremplis par URL** depuis le laissez-passer (section « Lot de poussins concerné » + identité) :
n° du dossier de laissez-passer (lien dossier, **197027**), importateur du lot (197029), date d'arrivée prévue
(197031), vol (197033), effectif attribué à l'élevage (197035), nom et prénom de l'éleveur (197038), téléphone
(197047).

**Saisis par l'éleveur** : adresse du lieu d'isolement (Te Fenua, 197045, avec mode d'emploi de la carte qui
**incite d'abord à cliquer sur la flèche de navigation** — géolocalisation, la carte se centre sur l'usager qui
remplit généralement depuis son élevage — puis à cliquer sur le bâtiment d'isolement pour poser le repère ;
le déplacement manuel n'est donné qu'en second recours), commune ou île (197044),
et **sept cases à cocher obligatoires, une par engagement** (197055 → 197049, numérotées 1 à 7, libellé court +
texte intégral en description, repris du formulaire Word) — préférées au bloc de texte unique : l'éleveur lit
et approuve chaque engagement séparément. Le titre « Engagements » (197043) porte la mention « le dépôt vaut
signature » et l'avertissement sur les sanctions.

Le dépôt vaut signature — horodatage et identité du compte. C'est le standard de la plateforme, mais
l'article 7 de l'arrêté n° 171 CM du 1er mars 2006 fait peser sur l'éleveur l'abattage total du lot à ses
frais exclusifs sans indemnisation : **une validation juridique explicite du service est requise**.

**Annotations privées** (section « Suivi robot ») : « Laissez-passer visé le » (**197028**, posée par le robot,
voir ci-dessous), « Certificat d'isolement établi le » (197030), « Date de levée d'isolement prévue » (197032,
J0 + 21 j, posée par le robot) ; section « Instruction » : carnet de notes (197036).

C'est cette démarche qui porte le **certificat d'isolement**, nominatif par élevage. **Il n'est pas produit au
dépôt de l'engagement mais au visa du laissez-passer** (décision du service, 11/09) : le certificat atteste
une mise en isolement, il n'a de sens qu'une fois le lot arrivé. Mécanique retenue, sans dépendre d'un
rafraîchissement du dossier engagement par la plateforme :

- au visa du laissez-passer, la tâche du dossier importateur retrouve les engagements rattachés et pose sur
  chacun l'annotation « Laissez-passer visé le » ; cette écriture modifie le dossier engagement, qui repasse
  donc en inspection, et sa tâche de publipostage se déclenche sur la présence de l'annotation ;
- un engagement déposé **après** le visa lit, à son dépôt, le visa du dossier importateur lié (champ lien
  dossier) et reçoit son certificat dans la foulée.

Les deux chemins mènent au même gabarit et à la même condition : « laissez-passer visé ET engagement déposé ».

**Comment le robot connaît les engagements rattachés.** L'API GraphQL de Mes-Démarches ne sait pas filtrer
les dossiers d'une démarche par la valeur d'un champ : le robot ne parcourt que les dossiers *modifiés depuis*
son dernier passage. Depuis le dossier importateur, ses engagements sont donc invisibles. **Le lien est
matérialisé dans Mes-Démarches, par une annotation privée du laissez-passer** (décision du 14/09) :

- au dépôt de l'engagement, sa tâche ouvre le dossier importateur désigné par le champ lien dossier
  (`DossierActions.on_dossier`) et **inscrit son numéro** dans l'annotation « Engagements reçus » du
  laissez-passer, via `SetAnnotationValue` — qui sait déjà écrire dans un autre dossier que celui en cours,
  y compris ajouter une ligne à un bloc répétable ;
- au visa, la tâche du laissez-passer **lit sa propre annotation** et pose « Laissez-passer visé le » sur
  chacun des engagements listés.

Forme de l'annotation (**révisée le 15/09**) : **deux zones de texte**, pas un bloc répétable — un bloc
répétable en annotation est fait pour saisir, pas pour lire, et son bouton « Supprimer » invite l'agent à
casser ce que le robot a écrit. Le robot **réécrit les deux zones en entier** à chaque engagement reçu, à
partir de la liste complète (pas d'ajout de ligne : ni doublon, ni dérive si l'agent a touché au texte) :

- **« Engagements reçus »** — une ligne par engagement, dans un format fixe que le robot écrit et relit
  lui-même, car il lui faut le **numéro de dossier** au visa :
  `Manutere TERE (manutere@exemple.pf) — dossier 654125 — déposé le 01/09/2026` — le courriel figure dans la
  ligne parce que c'est lui qui porte le rapprochement à la relecture. Un engagement dont le courriel ne
  correspond à aucune ligne du bloc éleveurs est listé quand même, avec la mention « non attendu » : c'est le
  cas qu'on veut voir remonter. **Invariant** : le robot doit pouvoir relire tout ce qu'il écrit (un nom ou un
  courriel vide ne fait pas disparaître la ligne).
  **Clé d'attribution (23/09)** : le rapprochement ne se fait plus sur le courriel du compte mais sur
  l'annotation privée **« Courriel d'attribution » (197081)** de l'engagement, **préremplie directement par le
  lien d'invitation** avec le courriel de la ligne du laissez-passer — le préremplissage par URL de
  Mes-Démarches s'applique aux annotations privées comme aux champs publics (vérifié dans le code de la
  plateforme, `PrefillChamps`), l'usager ne la voit pas et ne peut pas la modifier. Si elle est vide (démarche
  ouverte sans le lien), le robot la déduit du téléphone concordant, sinon du courriel du compte, et l'écrit.
  Le lien transporte ainsi l'identité de la ligne ; un éleveur qui signe avec un autre compte reste rattaché.
  L'agent peut corriger l'annotation à la main, ce qui relance le calcul. La recette doit produire une fois le
  cas « autre compte » et une fois le cas « démarche ouverte sans le lien ».
- **« Engagements manquants »** — les éleveurs du bloc « Liste des éleveurs » dont le courriel n'apparaît
  pas dans les reçus, **avec leur téléphone** pour que l'agent puisse les appeler :
  `Vaimiti HOA au 88 65 25 62 (vaimiti@exemple.pf)`. Elle se vide toute seule ; vide, l'agent sait qu'il
  peut viser.

Le rapprochement se fait par courriel, clé d'attribution de la spec (§4). Le **téléphone de l'éleveur est
demandé à l'importateur, obligatoire** (ajouté par l'utilisateur le 15/09) : il le connaît plus sûrement que
le courriel, et c'est la donnée qu'il faudra le jour du canal SMS (§8).

Pourquoi pas Grist : la table `Engagements` porte bien la colonne `Lot` et une requête SQL suffirait, mais
aucun processus du robot n'a encore fait dépendre un acte administratif d'un appel réseau vers un référentiel
externe qui peut être indisponible. **Une seule source de vérité, dans Mes-Démarches** ; Grist reste un miroir
de consultation. Idempotence : la tâche d'engagement n'écrit qu'une fois (numéro déjà présent → rien), comme
`SetAnnotation` le fait déjà pour une valeur existante.

### 3.3 Carnet de suivi

**Préremplis par URL** : n° du dossier importateur, nom de l'élevage, courriel, effectif attribué,
**date J0 = date de clôture du laissez-passer** (décision du service, 11/09 : c'est la date de référence de
l'isolement, pas la date d'arrivage déclarée par l'importateur).

**Champs usager** :
- en-tête d'accusé de réception (confirmation de l'effectif reçu et de la date) — seuls champs visibles à J0 ;
- champ formule **« Jour de suivi »** (`aujourd'hui − J0`), placé **avant** les champs conditionnés
  (contrainte de l'API de condition : le champ source doit précéder le champ conditionné) ;
- **21 champs nombre obligatoires**, chacun conditionné par `Jour de suivi >= N` ;
- bloc répétable **« jours supplémentaires »** pour les prolongations d'isolement — jusqu'à **21 jours de
  plus** au maximum, cas très rare (aucun en un an selon le service, 11/09) : le bloc répétable suffit, pas
  de seconde série de champs conditionnés ;
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

### 3.5 Paiement du laissez-passer

**Décision du 14/09 : le module de paiement fait partie du périmètre.** Le laissez-passer est une prestation
tarifée par l'arrêté n° 1920 CM (§11.5) et le prototype 3899 l'avait déjà prévu. Le module existant
`payzen/payment_order` (en production sur la généalogie DAF, prototypé sur la 3888) est réutilisé tel quel ;
ce qui suit est de la configuration.

**Barème** (arrêté 1920 CM, annexe 2, confirmé par le service le 17/09) : laissez-passer 500 F + déplacement
du vétérinaire 6 000 F dans les **horaires d'ouverture de la DBS**, ou 12 000 F en dehors, soit
**6 500 F ou 12 500 F**. **Les prélèvements de fonds de boîte ne sont pas facturés.**

**Ce que l'usager sait, ce que la vétérinaire décide** (18/09, **proposition soumise à l'équipe DBS**). L'usager
ne connaît ni la durée de l'examen (elle dépend de l'effectif, seule la vétérinaire la connaît) ni l'agenda de
la DBS : lui demander « l'heure de contrôle souhaitée » ou « l'heure de sortie souhaitée » produit une réponse
inventée, typiquement 7 h 30. En revanche il connaît deux **faits** : l'heure d'atterrissage du vol, et sa
**correspondance vers les îles** — un vol qui atterrit à 1 h 30 avec un bateau à 5 h impose de sortir avant 3 h,
et c'est cette contrainte de correspondance qui justifie un contrôle hors horaires. Le formulaire demande donc :

- « **Date et heure d'atterrissage du vol** » (107912, relibellé comme un fait) ;
- « **Les poussins repartent-ils vers une île le jour même ?** » (oui/non, **196862**) ; si oui :
  « **Correspondance** » (bateau / avion inter-îles / autre, **196863**), « **Départ de la correspondance** »
  (date-heure, **196864**), « **Heure à laquelle les poussins doivent avoir quitté l'aéroport** » (date-heure,
  **196865**, l'importateur connaît le temps d'acheminement jusqu'au quai).

La vétérinaire remonte le calcul et fixe « **Heure de rendez-vous du contrôle** » (annotation date-heure,
**196866**, section Véto). **C'est sa seule saisie** : le robot en déduit le tarif (18/09).

**Le tarif est calculé par le robot d'après l'heure de rendez-vous**, contre une **grille d'horaires d'ouverture
tenue dans la configuration YAML** (une plage par jour de semaine, modifiable sans déploiement). Convention à
confirmer par la DBS : c'est l'**heure de début** du rendez-vous qui compte. Les horaires ne figurent nulle part
dans le formulaire. Pour les cas que la grille ne sait pas traiter — jour férié, pont, situation particulière —
la vétérinaire coche « **Imposer le tarif** » (case à cocher, **196855**), ce qui fait apparaître « **Tarif
imposé** » (**196867**, *Dans les horaires DBS — 6 500 F* / *Hors horaires — 12 500 F*). La case à cocher est là
pour la charge mentale : un champ « tarif » visible en permanence serait rempli systématiquement ; caché
derrière une case, il ne sert qu'à déroger. Le robot n'embarque donc **pas de calendrier des jours fériés** :
c'est le forçage qui les couvre.

**Déclenchement en deux régimes** (décision du service, 17/09, déclencheur révisé le 18/09) :

| Correspondance déclarée | Déclencheur de la demande de paiement | Montant |
|---|---|---|
| non | **dès le dépôt** du dossier, automatiquement | 6 500 F |
| oui | **quand la vétérinaire renseigne « Heure de rendez-vous du contrôle »** — seule à savoir si le contrôle tient dans les horaires d'ouverture avant la correspondance | calculé : 6 500 F si le rendez-vous est dans la grille, 12 500 F sinon ; « Tarif imposé » s'il est renseigné |

Le robot n'a **aucune durée à calculer** : le régime se lit sur la réponse oui/non, et le tarif sur l'heure de
rendez-vous. Sans correspondance, il pose le montant et émet l'ordre sans attendre ; avec correspondance, il ne
fait rien tant que le rendez-vous est vide, puis pose le montant et émet l'ordre, avec l'heure de rendez-vous
dans le message. Un atterrissage dans les horaires avec correspondance déclarée passe quand même par la
vétérinaire : c'est elle qui confirme que le rendez-vous tient avant le bateau.

**Champs et annotations** (repris du prototype, corrigés) :

- champ usager « Paiement des frais » : *En ligne par carte / Virement / Au guichet* (existant, 68139) ; les
  textes d'explication sont à corriger — le virement dit 5 500 F, tarif du permis particulier hérité du clone ;
- annotations de la section Véto : **« Heure de rendez-vous du contrôle »** (196866, seule saisie de la
  vétérinaire), **« Imposer le tarif »** (case, 196855) et **« Tarif imposé »** (196867, affiché seulement si la
  case est cochée) ;
- annotations « Montant à payer » (**entier, initialisé par le robot** : 6 500 F sans correspondance, sinon
  d'après le créneau retenu ; **modifiable par l'agent**), « Demande de paiement » (identifiant PayZen), « Statut du
  paiement » (*Demandé / Payé / Expiré / Gratuit*), « Moyen de paiement » (*PayZen / Virement / Sur place*), « Expiration de la
  demande », « Visa régisseur » — le bloc régisseur du prototype, aligné sur la 3888.

**Cycle** : la demande de paiement part **dès le dépôt** (régime standard) ou **à la saisie du créneau** par le
vétérinaire (régime hors horaires) — dans les deux cas indépendamment de la cascade d'engagements, qui part au
passage en instruction ; rien ne s'attend. `quand_payé` pose le statut ; il **ne
fait pas accepter le dossier** (contrairement à la généalogie DAF), car la délivrance reste l'acte du
vétérinaire au visa. `quand_expiré` **ne classe pas sans suite** : les poussins arrivent physiquement et le
contrôle a lieu quoi qu'il en soit ; le robot relance l'importateur et alerte l'agent. Virement et guichet
suivent le circuit régie : le régisseur pose **« Payé »** à la main et renseigne « Moyen de paiement » (virement ou sur place) — c'est la combinaison des deux qui dit qu'un règlement est passé par la régie, il n'y a pas de statut dédié (18/09).

**Garde à la délivrance** : la tâche de publipostage du laissez-passer, déclenchée par le visa, vérifie que le
statut est *Payé* ou *Gratuit* ; sinon elle n'émet rien et le signale à l'agent. Le
vétérinaire garde la main (il peut poser *Gratuit*), le robot n'émet pas un acte impayé par inadvertance.

**La boutique PayZen de la régie DBS existe déjà** : le robot encaisse en production les laissez-passer
chats et chiens (`dbs_chat_chien.yml`, ancre `dbs_boutique`, démarches 1933 et 1950) avec clé de production.
Le bloc poussins réutilise cette ancre et le même schéma d'annotations ; aucune démarche auprès de la régie
pour ouvrir un compte. Deux différences assumées par rapport aux chats et chiens : pas de `dossier_accepter`
au paiement, pas de `dossier_classer_sans_suite` à l'expiration (voir *Cycle*).

**Réglé le 17/09** : lignes facturées = laissez-passer + déplacement, sans fonds de boîte. **Les horaires
d'ouverture ne sont écrits nulle part dans le formulaire ni dans le robot** (18/09) : ils varient (le vendredi
notamment) et la vétérinaire les connaît ; c'est son choix de créneau qui fait foi, pas une borne codée.
**Reste à confirmer** : le non-paiement ne bloque pas le contrôle à l'arrivée mais bloque la remise du laissez-passer.

**Deux sections pour un même tarif, volontairement** (18/09) : la section Véto porte la décision (heure de
rendez-vous, forçage éventuel) ; « Montant à payer » (section Régisseur, **entier**) est la valeur que le robot
**initialise** à partir de cette décision et que le régisseur lit. Redondant, mais les deux sections ne sont pas
regardées par les mêmes personnes.

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
préremplis, le second directement dans l'annotation privée « Courriel d'attribution » (§3.2, 23/09). Aucun jeton d'invitation spécifique n'est créé : le numéro de dossier est la référence
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

**Deux déclencheurs, deux courriels** (décision du service, 11/09) :

| Déclencheur | Événement sur le dossier importateur | Envoi | Pourquoi ce moment |
|---|---|---|---|
| n° 1 | dossier **en instruction** ET case **« Envoyer les engagements »** cochée par l'agent (révisé le 21/09) | lien prérempli vers l'**engagement** | l'engagement doit être signé *avant* l'arrivée des poussins ; un humain a vu le dossier et la liste avant que des dizaines de courriels partent. Le passage en instruction seul ne suffit pas : refuser ou classer sans suite impose de passer en instruction d'abord, un dossier refusé aurait déclenché les invitations |
| n° 2 | **visa** de l'agent habilité | lien prérempli vers le **carnet**, J0 = date de clôture du laissez-passer ; certificats d'isolement ; laissez-passer | le lot est là : l'isolement commence |

Chaque envoi est tracé **dans le laissez-passer lui-même** (22/09, cohérent avec la décision 17 : une seule
source de vérité) : l'annotation texte **« Invitations envoyées »** (197057) reçoit une ligne par éleveur,
`courriel — envoyé le JJ/MM/AAAA HH:MM`. C'est elle qui rend l'invitation non rejouable, et qui permet
d'inviter au passage suivant un éleveur ajouté à la liste après coup. Les dates d'envoi sont recopiées dans
Grist par la synchro, comme le reste. Anti-rejeu de la relance agent : annotation texte « Alertes délai »
(197058, mémoire de `dead_line_checker`).

> **Point à caler en plan** : « visé » et « clos » sont deux gestes de l'agent (annotation de visa, puis
> acceptation du dossier). Le service les considère comme un seul moment. Soit le robot accepte le dossier
> dans la foulée du visa, soit J0 est lu sur la date de visa — à trancher avec l'agent, l'écart est de
> quelques heures au plus.

**Quatre relances** :

| Relance | Déclenchement | Destinataire |
|---|---|---|
| **Envoi non déclenché** | dossier en instruction depuis 2 jours (calendaires : `dead_line_checker` ne connaît pas les jours ouvrés) sans « Envoyer les engagements » coché ; la relance planifiée est **annulée** quand la case est cochée | **agent** |
| Engagement non signé | quelques jours après l'invitation, puis à l'arrivée du lot | éleveur |
| Carnet non ouvert | pas d'accusé de réception du lot | éleveur **et vétérinaire** |
| Silence de 4 jours | carnet ouvert mais non tenu | éleveur |
| J21 | complétude du relevé, puis « lot mûr pour la visite de levée » | éleveur, puis vétérinaire |

**Un cas résiduel** : dossier dont les engagements ont été envoyés, puis refusé ou classé sans suite. Le robot
connaît les éleveurs invités : il leur envoie un courriel d'annulation.

**Une alerte**, distincte des relances : adressée à la cellule zoosanitaire **le jour même** quand, pour une
journée donnée, **le nombre de morts saisi est ≥ 3 % de l'effectif restant** ce jour-là — c'est-à-dire de
l'effectif reçu diminué des morts déjà déclarées les jours précédents (précision du service, 14/09 : « 3 % du
volume restant le jour de la mesure, pas du volume initial »). Le seuil reste un paramètre de configuration.
Le test est journalier, pas cumulé : 3 % le même jour est le signal d'une mortalité anormale, un cumul lent
sur 21 jours ne l'est pas. Rapporter au restant plutôt qu'à l'initial rend le seuil **plus sensible en fin
d'isolement** sur un lot déjà éprouvé, ce qui est le sens voulu. Le carnet porte déjà la formule « effectif
restant » (§3.3) : le robot compare `morts(J)` à `3 % × restant(J−1)`, avec `restant(J−1) = reçu − Σ morts(J' < J)`.

> L'engagement n° 2 impose de signaler immédiatement toute mortalité anormale, ce qui repose aujourd'hui
> entièrement sur l'initiative de l'éleveur. Le carnet quotidien rend la donnée lisible par le robot le
> jour même : un lot qui perd trente pour cent de son effectif à J4 est aujourd'hui découvert trois
> semaines plus tard, ou jamais. Gain de biosécurité réel, pour un coût marginal — le seuil est une règle
> de configuration — **fixée à 3 % de l'effectif restant, sur une journée** (réunion du 11/09, précisée le 14/09).

**Contrainte de mise en œuvre** : le curseur `checked_at` est partagé par démarche. Les relances de la
démarche carnet doivent être des tâches du **bloc existant**, pas un second bloc, sinon elles seraient
affamées.

---

## 6. Documents produits

Trois gabarits en publipostage v3, **à construire à partir des modèles Word vierges remis le 11/09** (mêmes
documents que les PDF annotés, en version éditable). Le modèle du certificat d'isolement contient encore
trois MERGEFIELD d'un ancien publipostage (`DocRef`, `Prop_Pays`, `AnimalNumID`) : à supprimer, ils ne
correspondent à aucune clé du robot et sortiraient tels quels.

| Gabarit | Démarche | Portée |
|---|---|---|
| `laissez-passer.docx` | importateur | un par lot, à la délivrance |
| `certificat-isolement.docx` | engagement | un par éleveur, nominatif, **au visa du laissez-passer** |
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
clé, du document papier jusqu'à la table Grist.** Confirmé par le service le 11/09 : le chrono des documents
est le numéro de dossier, sans mise en forme particulière. Le permis d'importation préalable reste saisi tant qu'il n'est pas dématérialisé.

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
- **Tableau des articles réglementés** du laissez-passer : **une seule ligne, confirmé le 11/09** (un
  dossier = un type, ponte ou chair ; code NC 010511, *Gallus gallus*). Pas de boucle de tableau.

---

## 7. Décisions tranchées

| # | Décision | Alternative écartée |
|---|---|---|
| 1 | Trois démarches neuves | Greffe sur un existant : aucune démarche poussins n'existe |
| 2 | Classeur joint côté importateur | Bloc répétable : plusieurs dizaines d'éleveurs par import, l'importateur a déjà son fichier |
| 3 | Cascade **non bloquante** | Blocage du laissez-passer sur les engagements : un éleveur silencieux immobiliserait tout le lot |
| 4 | Déclenchement des engagements par une **case « Envoyer les engagements »** cochée par l'agent, dossier en instruction (révisé le 21/09) | Passage en instruction seul : obligatoire avant tout refus ou classement, donc un dossier refusé invitait ses éleveurs ; au dépôt : courriels partis avant toute vérification ; délai « en instruction depuis 2 h » : complexité pour un gain faible. Le risque d'oubli du geste est couvert par une relance à l'agent |
| 5 | Carnet ouvert dès J0, relance J21 pour compléter | Création à J21 : saisie rétroactive de 21 jours de mémoire |
| 6 | **Dossier déposé dès J0**, en construction | Brouillon 21 jours : invisible du robot, ni relance ni alerte possibles |
| 7 | 21 champs obligatoires masqués par condition | Bloc répétable (case vide = ligne absente, complétude non garantie) ; classeur côté éleveur (tableur non garanti) |
| 8 | Référentiel clé courriel, n° Tahiti par l'aval | Référentiel en *entrée* : ressaisie imposée à l'importateur |
| 9 | Numéro de dossier comme référence unique | Chrono maison par série et par millésime |
| 10 | Copies = courriel d'information + accès Grist | Envoi de pièces jointes : non supporté, et inadapté à une diffusion |
| 11 | Deux courriels : engagement à l'instruction, carnet au visa (11/09) | Un seul courriel à deux liens : l'engagement doit précéder l'arrivée, le carnet ne peut pas la précéder |
| 12 | Certificat d'isolement publiposté au visa du laissez-passer (11/09) | Au dépôt de l'engagement : le certificat atteste une mise en isolement, le lot n'est pas encore là |
| 13 | J0 = date de clôture du laissez-passer (11/09) | Date d'arrivage déclarée par l'importateur : prévisionnelle, pas constatée |
| 14 | Alerte si morts du jour ≥ 3 % de l'effectif **restant** la veille (11/09, précisé 14/09) | Seuil cumulé : ne détecte pas un pic ; base « effectif initial » : moins sensible en fin d'isolement |
| 15 | Un dossier = un type de poussins, ponte ou chair (11/09) | Lot mixte avec boucle de tableau : le service dépose deux dossiers |
| 16 | Prolongation par bloc répétable, plafond 21 jours (11/09) | Seconde série de 21 champs conditionnés : cas trop rare pour le coût |
| 17 | Rattachement engagements → laissez-passer par deux **zones de texte** « Engagements reçus » / « Engagements manquants » sur le laissez-passer, réécrites en entier par le robot (14/09, forme révisée 15/09) | Requête SQL Grist au visa : dépendance réseau à un référentiel externe pour un acte administratif, double source de vérité |
| 19 | LTA et certificat sanitaire : pièces jointes **facultatives** avec consigne « messagerie, 24 h avant l'avion » ; **données relevées par l'agent** en annotations (17/09) | Champs usager obligatoires : documents émis après le dépôt, références souvent fausses (dossiers dupliqués) |
| 20 | Pas de facturation des fonds de boîte (17/09) | Ligne « + 3 000 F » du barème : non pratiquée par le service |
| 21 | Listes de contrôle agent du laissez-passer chats/chiens supprimées (17/09) | Les garder : vérifications simples ici ; à remettre sur demande |
| 22 | **Proposition (18/09, à valider par la DBS)** : l'usager déclare l'atterrissage et sa correspondance vers les îles ; la vétérinaire fixe l'heure de rendez-vous ; le régime de paiement se lit sur « correspondance oui/non » | Demander une heure de contrôle ou de sortie souhaitée : l'usager ne connaît ni la durée de l'examen ni l'agenda, il répond 7 h 30 par réflexe |
| 23 | **Tarif calculé par le robot** d'après l'heure de rendez-vous et une grille d'horaires en configuration YAML ; forçage derrière une case « Imposer le tarif » pour fériés et cas rares (18/09) | Menu « créneau retenu » saisi par la vétérinaire : double saisie avec le rendez-vous ; champ « tarif imposé » toujours visible : rempli systématiquement par réflexe ; calendrier des fériés dans le robot : maintenance annuelle pour des cas rares |
| 18 | **Module de paiement dans le périmètre** : `payzen/payment_order` dès le dépôt (horaires DBS) ou à la saisie du créneau par le vétérinaire (hors horaires), statut vérifié au visa, expiration → relance sans classement (14/09, régimes précisés 17/09) | Hors périmètre (devis d'août) : le laissez-passer est tarifé et le prototype le prévoyait ; classement sans suite à l'expiration : le lot arrive physiquement, le contrôle a lieu de toute façon |

---

## 8. Réserves et questions ouvertes

**Réserves à lever pendant le projet**

1. **Validation juridique** de la case « lu et approuvé » comme signature de l'engagement, au regard de
   l'article 7 (abattage total aux frais de l'éleveur, sans indemnisation).
2. **Validation des champs obligatoires à l'enregistrement** d'un dossier en construction — si elle ne
   s'applique pas, la progressivité côté robot prend le relais (déjà chiffrée).
3. ~~Seuil de mortalité~~ — **réglé le 11/09, précisé le 14/09** : morts du jour ≥ 3 % de l'effectif restant.

**Questions au service** (non abordées le 11/09, toujours ouvertes)

- ~~Forme exacte de la référence documentaire dans les gabarits.~~ — **réglé le 11/09** : le chrono des
  documents est le numéro de dossier Mes-Démarches, tel quel.
- Liste de diffusion électronique des laissez-passer.
- Confirmation que les champs barrés du formulaire importateur le sont parce que Mes-Démarches connaît le
  déposant.
- ~~Un lot peut-il mélanger ponte et chair ?~~ — **réglé le 11/09** : un dossier par type.

**Demande nouvelle, à chiffrer à part : notifications par SMS.** Les éleveurs sont souvent dans des lieux
reculés sans connexion fiable ; le service demande si les liens d'invitation et les alertes peuvent partir
par SMS. Le robot n'a aujourd'hui aucun canal SMS : il faut une passerelle (opérateur local ou service tiers),
un numéro de mobile par éleveur dans le classeur, et une politique de repli courriel ⇄ SMS. Non spécifié ni
chiffré ici ; le besoin est noté pour un devis ultérieur.

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

Répartition de la réalisation : **CC** = Claude Code (code, configuration, champs via MCP, formules
Grist), **Dév.** = le développeur (actes non outillés : création et publication des démarches, mise en
page Word, recette live, déploiement), **DBS** = le service (décisions métier et validation).

| Poste | Contenu | Réalisation | Charge |
|---|---|---|---|
| **1. Conception des démarches** | Création des coquilles et publication | Dév. | **1 j** |
| | Champs, annotations, blocs répétables, formule « Jour de suivi », 21 conditions | **CC** (MCP) | |
| | Modèle de classeur `.xlsx` | **CC** | |
| | Relecture ergonomique et validation | Dév. + DBS | |
| **2. Cascade d'invitation** | Relevé des ids base64 des champs préremplis | **CC** | **1 j** |
| | Construction des URL, tâche d'envoi, idempotence, horodatage Grist, specs | **CC** | |
| | Revue de code | Dév. | |
| **3. Référentiel Grist** | Doc, tables, colonnes, colonnes `Ref`, formules de rapprochement | **CC** (MCP) | **1 j** |
| | Configuration `mes_demarches_to_grist` et `excel_vers_grist` | **CC** | |
| | Validation du tableau de bord avec le vétérinaire | DBS | |
| **4. Contrôles et relances** | Plugins, configuration YAML, specs, rédaction des courriels | **CC** | **1 j** |
| | Seuil de mortalité, validation des textes | DBS | |
| **5. Documents** | Annexes de fusion (`bin/generer_annexe`), structure et MERGEFIELD | **CC** | **1,5 j** |
| | Mise en page fidèle : en-tête, logo, QR code, mentions de recours | Dév. + DBS | |
| | Configuration publipostage v3 et visas | **CC** | |
| **6. Recette et déploiement** | Jeux de test, classeur fictif, scénario bout en bout, **scénarios de paiement** (payé, expiré, gratuit, régie) | **CC** | **3 j** |
| | Exécution sur staging avec comptes usagers réels, accompagnement | Dév. + DBS | |
| | `mirror_staging.sh` puis `mirror_production.sh` | Dév. | |
| **7. Paiement** *(ajouté le 14/09)* | Annotations du bloc Paiement via MCP, configuration `payzen/payment_order`, **calcul du tarif d'après l'heure de rendez-vous et la grille d'horaires en YAML**, forçage, garde à la délivrance, textes des messages | **CC** | **1 j** |
| | Réutilisation de la boutique PayZen DBS (`dbs_chat_chien.yml`), tests en mode test puis premier paiement réel avec le régisseur | Dév. + DBS | |
| | Correction des textes d'explication du formulaire (montants, IBAN) | DBS | |
| | | **Total** | **≈ 9,5 j** |

### Méthode d'estimation

Les charges ne sont **pas** homogènes en productivité. Les postes majoritairement codés ou configurés
(2, 3, 4) sont estimés au tiers d'un barème classique ; les postes à part humaine incompressible — mise en
page Word, recette avec de vrais comptes, accompagnement du service, déploiement — ne bénéficient que
marginalement de l'outillage. Le facteur global se situe autour de 2,5, avec ~3 sur le code et ~1,5 sur
le reste.

### Charge n'est pas délai

Trois éléments allongent le calendrier sans consommer de charge : la validation juridique de la signature
de l'engagement, l'obtention de la liste de diffusion, et la disponibilité du régisseur pour le premier
paiement réel (le seuil de mortalité est fixé depuis le 11/09 ; la boutique PayZen existe déjà).

**Un risque calendaire propre à ce projet** : le cycle métier dure 21 jours. Le J21 ne se teste pas en
conditions réelles en une journée. La recette devra jouer sur la **date d'arrivage** — c'est un champ, donc
falsifiable sur un dossier de test — pour simuler l'écoulement du temps et vérifier l'apparition
progressive des champs conditionnés ainsi que le déclenchement des relances. À défaut, prévoir un lot
pilote réel sur trois semaines **en parallèle** du reste du chantier, pas en séquence.

> **La colonne de réalisation ne réduit pas la charge.** Les jours annoncés sont la charge du chantier,
> revue humaine et allers-retours compris. Ce que Claude Code réalise reste à relire, à corriger et à
> valider — la répartition dit *qui tient le clavier*, pas *combien ça coûte*.

**Actes hors de portée de Claude Code**, à prévoir côté développeur : créer et publier une démarche
(l'API de configuration modifie les champs d'une démarche existante, elle ne crée pas la démarche),
produire une mise en page Word fidèle à un document officiel, exécuter la recette live avec de vrais
comptes usagers, et déployer.

**Poste ajouté le 14/09** : le paiement (poste 7, 1 j + 0,5 j de recette). Le module est en production
ailleurs ; la charge est celle de la configuration, du calcul du montant, et de la recette avec le régisseur —
la boutique PayZen de la DBS est déjà en production pour les chats et chiens, ce qui ôte le principal aléa.

**Postes supprimés en cours de cadrage** (documentés pour mémoire) : numéroteur séquentiel réglementaire,
client REST de préremplissage — l'URL `?ChampId=Valeur` suffit — et gestion du nom du signataire dans les
gabarits, déjà couverte par le visa et `email_to_names`.

**Options non chiffrées** : table Baserow globale des agents par service (généralisation de
`email_to_names`), besoin non posé ; **canal SMS** pour les invitations et alertes, demandé le 11/09, à
chiffrer à part (passerelle + numéros de mobile + repli).

---

## 10. Compte rendu de la réunion du 11/09/2026

Réponses du service, intégrées dans les sections ci-dessus :

| Sujet | Réponse | Impact |
|---|---|---|
| Modèles de documents | Les trois modèles Word vierges sont remis, plus la fiche de suivi Excel (J0 à J21) | Base des gabarits v3 (§6) ; vieux MERGEFIELD à purger |
| Certificat d'isolement | Publiposté **automatiquement au visa du laissez-passer** par l'agent | Mécanique via annotation « Laissez-passer visé le » (§3.2) |
| Engagement | Rempli par l'éleveur **avant l'arrivée** des poussins → invitation au passage en instruction | Inchangé, confirmé (§5) |
| Carnet de suivi | Invitation **au visa** du laissez-passer ; **J0 = date de clôture** du laissez-passer | Deux courriels au lieu d'un ; J0 prérempli depuis le dossier importateur (§3.3, §5) |
| Seuil de mortalité | Alerte si, un jour donné, **morts ≥ 3 % de l'effectif restant** (précision du 14/09 : restant, pas initial) | Règle de configuration fixée (§5) |
| Chrono des documents | **C'est le numéro de dossier Mes-Démarches** | Décision 9 confirmée ; plus de « forme de la référence » à fixer (§6) |
| Lot mixte | **Un dossier = un type** (ponte ou chair) ; deux types → deux dossiers | Tableau du laissez-passer à une ligne, pas de boucle (§6) |
| Prolongation | Jusqu'à **21 jours de plus**, extrêmement rare (aucun cas en un an) | Bloc répétable suffisant (§3.3) |
| SMS | Souhait d'envoyer liens et alertes par SMS (éleveurs sans internet) | Hors périmètre, à chiffrer plus tard (§8) |

**Ajout du 14/09** : module de paiement retenu au devis (décision 18, §3.5, poste 7) → total ≈ 9,5 j.

**Proposition du 18/09, soumise à l'équipe DBS** (décision 22) : plus d'heure « souhaitée » demandée à l'usager ;
il déclare l'atterrissage et sa correspondance vers les îles (bateau ou avion, départ, heure limite de sortie),
la vétérinaire fixe le rendez-vous, le paiement part dès le dépôt sans correspondance et au créneau retenu
avec. Champs créés sur la 3899 pour la revue.

**Correction du 21/09** (décision 4 révisée) : le passage en instruction ne peut pas déclencher les invitations,
puisqu'il précède obligatoirement un refus ou un classement sans suite ; déclencheur = case « Envoyer les
engagements » cochée par l'agent, avec relance à l'agent au bout de 2 jours ouvrés et courriel d'annulation
aux éleveurs si le dossier est refusé après envoi.

**Retours du service sur la démarche, 17/09** (décisions 18 à 21) : pas de facturation des fonds de boîte ;
paiement dès le dépôt sans correspondance vers une île, sinon à la saisie du créneau par la vétérinaire ;
LTA et certificat sanitaire en pièces jointes facultatives (consigne « messagerie, 24 h avant l'avion ») et
données relevées par l'agent ; champs hérités du laissez-passer chats/chiens retirés, listes de contrôle
supprimées jusqu'à demande contraire. Sans effet sur le devis : tout est configuration.

Restent ouvertes : validation juridique de la signature de l'engagement, liste de diffusion électronique,
sens des champs barrés du formulaire importateur et collecte du
certificat sanitaire / déclarant en douane.

---

## 11. Prototype 3899 — analyse critique (14/09/2026)

Lecture de la révision brouillon via `lire_demarche` et `bin/describe_demarche 3899`. La démarche est un
**clone du laissez-passer animaux de compagnie** : le bloc paiement, la section « CHECK RÉGISSEUR », une
annotation « test Leishmaniose » et des options résiduelles de listes (« chien d'assistance », « cachet du
laboratoire ») en témoignent. Ce qui suit distingue ce qu'il faut **garder**, **corriger**, **arbitrer** avec
la spec, et **ajouter**.

### 11.1 À garder

- **Section « Informations sanitaires »** (certificat zoosanitaire en PJ, n° du certificat, vétérinaire
  officiel signataire en liste, date de signature), **non obligatoire** avec la consigne « à remplir dès
  réception » : c'est exactement la réponse à la question ouverte « collecter le certificat sanitaire en
  amont ». Le vétérinaire n'aura plus à le ressaisir.
- **N° Tahiti** en type `Siret` (192140) et **n° de permis d'importation préalable** (132715) avec le format
  attendu en description — les deux champs « à rajouter » du formulaire papier sont là.
- **Listes fermées avec « autre »** pour le vol (NZ 902), l'exportateur (Tegel, Bromley Park), les races
  (Shaver Brown / Hyline Brown en ponte, Cobb / Ross 308 en chair) : bonne ergonomie, et l'annotation
  « Importateur » avec la dénomination exacte des PIP est une vraie valeur ajoutée pour le publipostage.
- **LTA** : numéro + pièce jointe obligatoires (181905, 192135).
- **Sections d'annotations « CHECK TECHNICIEN » / « CHECK VÉTO »** : la logique de double contrôle du
  service est lisible ; on la garde, on en change les outils (visa nominatif, voir 11.2).

### 11.2 À corriger avant publication

**Bloquant pour le robot**

| # | Constat | Correction |
|---|---|---|
| C1 | **« Destination du poussin » (181906) est une liste à choix multiples** : Ponte *et* Chair cochables ensemble | Liste à **choix unique** — un dossier = un type (décision 15). Elle pilote aussi les conditions des deux champs « Race » |
| C2 | **Deux champs « Race »** publics (75477, 188540) et **deux « Exportateur »** (188529, 188542) et **deux « Quantité totale »** (65381, 181894) portent le **même libellé** | Le publipostage v3 normalise les libellés en clés : collision, panne silencieuse. Renommer (« Race ponte » / « Race chair » comme les annotations l'ont déjà fait) ; supprimer le second « Exportateur » (la liste a déjà « autre ») ; renommer ou supprimer le second « Quantité totale » |
| C3 | Le bloc « Liste des éleveurs » (132719) demande à l'importateur le **n° de dossier du certificat d'isolement de l'éleveur** (188462) | **Impossible par construction** : dans la cascade, l'engagement n'existe pas encore au dépôt du laissez-passer. Supprimer. Le lien se fait dans l'autre sens (engagement → laissez-passer) puis par l'annotation « Engagements reçus » (§3.2) |
| C4 | Le bloc éleveurs exige **adresse Te Fenua et téléphone** de chaque éleveur | L'importateur ne les connaît pas de façon fiable ; ils arrivent **par l'aval**, saisis par l'éleveur dans son engagement (décision 8). Ne garder que nom de l'élevage / éleveur, courriel, commune ou île, quantité |
| C5 | Aucun champ public **« Date d'arrivée »** ; seule l'annotation privée 192136 existe. « Heure de sortie » (107912, datetime, hérité des animaux de compagnie) tient lieu d'arrivée | Le formulaire papier a « Date d'arrivée » côté importateur et le laissez-passer l'imprime. Renommer 107912 en « Date et heure d'arrivée du vol » ou ajouter un champ date public |
| C6 | Visa : « LP validé par un véto » Oui/Non (79305) + « Vétérinaire instructeur » (79236) + « Signataire » (79235) en **listes de noms** | Remplacer par un **champ visa nominatif** (`VisaChamp`) « Visa de l'agent habilité » : identité et horodatage garantis, et c'est le **déclencheur n° 2** (§5). Le nom du signataire vient de `email_to_names`. Les listes actuelles contiennent d'ailleurs un doublon (« Clément DUSSOT » / « DUSSOT Clément ») et un ordre nom/prénom mélangé |

**Ménage du clone**

| # | Constat | Correction |
|---|---|---|
| M1 | Annotation « Date de fin de validité du test Leishmaniose » (78626) | Supprimer |
| M2 | Annotations `DossierLink` « Numéro de dossier déposé sur %{app_name} test » (192132) et « Destinataire » (192141, description « --Ile A-- Eleveur 1… ») | Supprimer ; le placeholder `%{app_name} test` fuit aussi dans le libellé du champ 188462 |
| M3 | Annotation « LTA » (78607) en texte, avec options « Primo-vaccination / Revaccination » ; « Nombre de poussins » (78615) avec options « Cachet du laboratoire… » ; « Nombre de colis » annotation (192146) en texte alors que le champ public est un entier | Débris d'options : sans effet à l'écran mais à nettoyer ; aligner les types |
| M4 | **« CHECK VÉTO »** existe deux fois : une case à cocher (78562, position 22, rangée dans « Description des articles ») et un titre de section (79304) | Supprimer la case, garder le titre |
| M5 | « Commune et Île » (188460) **et** « Code Postal de Polynésie » (188459), tous deux `CodePostalDePolynesie` | Un seul suffit, le type porte commune et code |
| M6 | « Responsable » (188461) = civilité en **liste à choix multiples** | Choix unique, libellé « Civilité » |
| M7 | « Date du PIP » (79302) décrite comme « date d'émission du laissez-passer… même que la date d'arrivée » | Libellé et description se contredisent (PIP = permis préalable). Clarifier ou supprimer ; la date d'arrivée existe déjà |
| M8 | « Quantité totale » (181894) est un champ **texte formaté** censé faire « l'addition des quantités de chaque éleveur » | Un champ texte n'additionne rien. Soit un champ formule, soit rien : le robot contrôle la somme (classeur vs effectif total) |
| M9 | « Quantité » (181895) en texte | Entier |

**Double saisie agent / usager**

La section d'annotations « Informations sur l'import » et « Description des articles » **redouble** neuf champs
publics (pays, vol, date d'arrivée, LTA, expéditeur, effectif, destination, races, colis). C'est le schéma du
laissez-passer animaux, où l'agent ressaisit pour corriger avant publipostage. Avec le robot, le publipostage
lit directement les champs usager : **supprimer ces annotations**, sauf une — « Importateur » (192139),
dénomination exacte du PIP, qui est un vrai **forçage** métier à conserver.

### 11.3 Divergences avec la spec, à arbitrer

| # | Prototype | Spec | Proposition |
|---|---|---|---|
| D1 | **Bloc répétable** « Liste des éleveurs » | **Classeur joint** (décision 2 : plusieurs dizaines d'éleveurs, l'importateur a déjà son fichier) | Garder le classeur si la volumétrie annoncée se confirme ; le bloc répétable reste acceptable en dessous d'une dizaine de lignes, mais on perd `excel_vers_grist` et l'annuaire complet. **Demander au service le nombre d'éleveurs par import** |
| D2 | **« Lieux d'isolement : Chez vous / Chez des éleveurs »** | Non traité : la spec suppose des éleveurs tiers | **Trou de la spec, révélé par le prototype.** L'importateur qui isole lui-même est un éleveur comme les autres : il figure comme ligne de destinataire (son propre élevage) et reçoit engagement + carnet. Une seule mécanique, pas de cas particulier. À confirmer avec le service |
| D3 | **Bloc paiement complet** (500 F laissez-passer + 6 000 / 12 000 F inspection, PayZen / virement / guichet) et section « CHECK RÉGISSEUR » | **Aucun paiement** dans la spec ni le devis | **Le laissez-passer est une prestation tarifée** (recherche du 14/09, §11.5) : 500 F le laissez-passer, 6 000 / 12 000 F le déplacement du vétérinaire, 3 000 F le prélèvement de fonds de boîte par lot. Les montants du prototype sont donc les bons ; le **5 500 F** du texte virement est le tarif « permis d'importation, particulier, par animal » hérité du clone animaux de compagnie — **faux ici**. Reste à confirmer avec le service qu'il **facture effectivement** le laissez-passer poussins (le papier n'en parle pas) et selon quel détail. **Tranché le 14/09 : le module de paiement entre au devis** (poste 7, §9 ; conception §3.5) |
| D4 | Nom, prénom, civilité, adresse géographique, téléphone, courriel du responsable **obligatoires** | Champs **barrés** sur le formulaire papier | Toujours la question ouverte n° 3 ; le prototype tranche dans le sens inverse des annotations du service |
| D5 | « Provenance » propose **Nouvelle-Calédonie** | Les modèles Word du certificat et de l'engagement écrivent « originaires de Nouvelle-Zélande » en dur | Soit la liste se limite à NZ, soit les gabarits prennent un champ de fusion « Provenance » |

### 11.4 À ajouter

- **Déclarant en douane** : imprimé sur le laissez-passer, absent du prototype comme du papier.
- **Classeur des destinataires** en pièce jointe (si D1 est tranchée dans le sens de la spec) + modèle `.xlsx`.
- **Annotations** : bloc répétable **« Engagements reçus »** (§3.2), **visa** de l'agent habilité (C6),
  **date de délivrance**. L'explication « Robot » et le texte « Rappel » (121103, 121104) existent déjà et
  servent la messagerie du robot.
- **Titre** : « volailles d'un jour - TIM » → « poussins d'un jour » (le TIM est un vestige).

### 11.5 Recherche du 14/09 — le laissez-passer est-il payant ?

**Oui, en droit.** Les prestations de la biosécurité sont tarifées par l'**arrêté n° 1920 CM du 26 novembre
2015** « fixant les tarifs des prestations du service en charge de la biosécurité » (JOPF n° 97 du 04/12/2015,
p. 13124), modifié par l'arrêté n° 455 CM du 11 avril 2017, pris en application de l'art. LP 56 de la loi du
pays n° 2013-12. Son annexe 2 (qualité alimentaire et action vétérinaire) fixe, pour les échanges
internationaux :

| Prestation (annexe 2, arrêté 1920 CM) | Tarif |
|---|---|
| Laissez-passer vétérinaire ou zoosanitaire à l'importation, à l'unité | **500 F** (forfaits : 10 pour 4 500 F, 50 pour 20 000 F, 100 pour 30 000 F, 200 pour 50 000 F, 300 pour 70 000 F ; au-delà 200 F l'unité) |
| Dépôt d'une demande de **permis d'importation préalable**, animaux vivants | particulier : 5 500 F par animal ; **professionnel, valable un an : 7 500 F** |
| Intervention à la demande, contrôle ou opérations d'office, Tahiti, heures légales | technicien 4 000 F, **vétérinaire 6 000 F** par déplacement |
| Idem, hors heures légales | technicien 8 000 F, **vétérinaire 12 000 F** par déplacement |
| Idem, île autre que Tahiti | déplacement aux frais du demandeur, intervention au même tarif |
| **Prélèvement de fonds de boîte de poussins à l'aéroport** et dépôt au laboratoire (opération d'office) | **3 000 F par lot** |
| Prélèvements dans le cadre des autocontrôles obligatoires | 6 500 F par bâtiment, analyses aux frais du demandeur |
| Séjour en quarantaine animale à l'aéroport | 5 000 F par jour |
| Autre document officiel à l'importation / exportation | 2 000 F ; duplicata 500 F |

La page « Volailles et œufs à couver » du site de la DBS affiche un encadré *Tarifs* cohérent : « Certificat à
l'unité : 500 XPF — Permis d'importation préalable : 7 500 XPF ». Sources : fiche Lexpol de l'arrêté
(`lexpol.cloud.pf/LexpolAfficheTexte.php?texte=459542`, texte consolidé en .doc dont les annexes sont des
images, lues par OCR) ; page DBS
`service-public.pf/biosecurite/accueil/professionnels-2/importer-en-polynesie-francaise-2/animaux-vivants/importation-de-volailles/`.

**Conséquences pour la démarche :**

- Les montants du prototype 3899 — 500 F + 6 000 ou 12 000 F, soit 6 500 / 12 500 F — **correspondent au
  barème** (laissez-passer + déplacement du vétérinaire pour le contrôle physique à l'arrivée). Le texte du
  virement (5 500 F, « 46,10 € ») est le tarif du permis d'importation *particulier par animal* : un débris du
  clone animaux de compagnie, à corriger.
- Le **prélèvement de fonds de boîte, 3 000 F par lot**, est une opération d'office propre aux poussins :
  l'ajouter au barème du formulaire s'il est facturé (le prototype ne le prévoit pas).
- Le **permis d'importation préalable** (7 500 F, professionnel, valable un an) est une prestation distincte,
  demandée deux mois avant l'arrivée ; la DBS publie un formulaire Word « 268bis - Demande de permis
  d'importation Poussins-Poissons ». Il reste hors périmètre (le n° de permis est saisi dans le laissez-passer),
  mais c'est une démarche candidate à dématérialiser plus tard.
- **Ce que la recherche ne dit pas** : si la DBS facture *aujourd'hui* le laissez-passer poussins par ce
  circuit (le formulaire papier annoté ne mentionne aucun paiement), si le montant est dû par lot ou par
  dossier, et si le paiement conditionne la délivrance. **À poser au service.** Le module est **retenu au devis** (poste 7) ; ces réponses en règlent le détail,
  pas le principe.

**Trouvaille annexe** : la même page DBS publie un « Tableau de suivi des autocontrôles » Word pour les
volailles d'un jour (dépistage Salmonella : 5 garnitures de fonds de boîte à l'aéroport, puis chiffonnettes aux
semaines 14, 20, 35, 50, 65, 80, 95 ; arrêté n° 1651 CM du 15/11/2012). C'est un **second suivi long**, distinct
de l'isolement de 21 jours et hors périmètre — à noter pour une suite éventuelle.

### 11.6 Corrections appliquées le 14/09/2026 (révision brouillon, via MCP)

**Fait**

- C1 : « Destination des poussins » (181906) → liste à **choix unique** Ponte / Chair, description « un dossier
  = un type » ; conditions des deux races redéfinies dessus.
- C2 : « Race ponte » (75477) / « Race chair » (188540) ; second « Exportateur » (188542) et « Quantité totale »
  formatée (181894) supprimés.
- C3 / C4 : dans « Liste des éleveurs », suppression du lien dossier (188462), de l'adresse Te Fenua (132720) et
  du téléphone (132722) ; ajout de « Nom de l'élevage » (**196207**) ; description réécrite (l'éleveur saisit
  lui-même n° Tahiti et lieu d'isolement).
- C5 : « Heure de sortie » (107912) → **« Date et heure d'arrivée du vol »**, avec la mention du tarif doublé
  hors heures légales.
- C6 : annotation **« Visa de l'agent habilité »** (type visa, **196201**) et **« Date de délivrance du
  laissez-passer »** (**196206**) dans CHECK VÉTO ; listes « Vétérinaire instructeur » (79236) et « Signataire »
  (79235) supprimées.
- M2, M3, M4, M5, M7, M8, M9 : débris du clone, doublon CodePostal, case « CHECK VÉTO », « Date du PIP »,
  « Quantité totale » texte supprimés ; « Quantité » (181895) → entier positif, libellé « Quantité de poussins
  isolés chez vous » ; M6 : « Civilité du responsable » (188461) en choix unique.
- Double saisie : annotations pays, vol, date d'arrivée, LTA, expéditeur, effectif, races, colis, n° de permis
  supprimées, ainsi que les titres « Informations demandeurs » et « Description des articles » ; **« Importateur »
  (192139) conservée** comme forçage.
- Ajouts : champ public **« Déclarant en douane »** (**196200**, section transport) ; bloc répétable privé
  « Engagements reçus » (196202, enfants 196203-196205) — **à remplacer le 15/09 par deux zones de texte**
  « Engagements reçus » et « Engagements manquants » (§3.2), le bloc n'étant pas lisible en annotation.
  Téléphone de l'éleveur remis **obligatoire** dans « Liste des éleveurs » par l'utilisateur.
- Paiement (§3.5) : « Montant à payer » (79230) → liste 6 500 / 12 500 / 9 500 / 15 500 F avec « autre » ;
  « Statut du paiement » (79233) → Demandé / Payé / Expiré / Gratuit (« Réglé en régie » retiré le 18/09 : c'est Payé + Moyen de paiement qui porte l'information) ; texte du virement
  (112730) corrigé (plus de 5 500 F, montant renvoyé à la demande de paiement, régie DBS).

**Fait le 15/09** : bloc 196202 supprimé, remplacé dans CHECK VÉTO par les zones de texte **« Engagements
reçus » (196270)** et **« Engagements manquants » (196271)** ; les deux zones d'essai créées la veille pour les
captures (196252, 196253) supprimées ; « Date de fin de validité du test Leishmaniose » (78626), annotation
« Destination des poussins » (192142) et « LP validé par un véto » (79305) supprimées. Dans « Liste des
éleveurs », l'utilisateur a ajouté **« Téléphone de l'éleveur »** (196213, obligatoire, passé en type téléphone)
; « Email de l'éleveur » (181893) est **obligatoire** (décision du 15/09 : les invitations ne partent que par
courriel tant qu'il n'y a pas de passerelle SMS, et l'éleveur a de toute façon besoin d'une adresse pour
remplir son dossier sur Mes-Démarches). Le rapprochement engagement ↔ attribution reste par courriel (§4).

**Volontairement laissé en attente d'arbitrage** : D1 (bloc répétable conservé, nettoyé ; classeur non ajouté),
D2 (« Lieux d'isolement : chez vous » conservé tel quel), D4 (champs du responsable toujours obligatoires),
D5 (Nouvelle-Calédonie toujours proposée), titre de la démarche (« volailles d'un jour - TIM », non modifiable
par l'API de configuration), IBAN du texte de virement (à faire confirmer par la régie DBS), fonds de boîte
(3 000 F) dans le barème.

**Fait le 21/09** : case à cocher privée **« Envoyer les engagements »** (**196946**, section Instruction, après
« Carnet de notes ») — déclencheur n° 1 de la cascade (décision 4 révisée).

**Fait le 18/09 (proposition pour l'équipe DBS, à valider)** : « Date et heure d'arrivée du vol » (107912)
relibellé « Date et heure d'atterrissage du vol » ; ajout dans la section transport de « Les poussins
repartent-ils vers une île le jour même ? » (oui/non, **196862**) et, conditionnés à « oui », « Correspondance »
(**196863**), « Départ de la correspondance » (**196864**), « Heure à laquelle les poussins doivent avoir quitté
l'aéroport » (**196865**) ; annotation « Heure de rendez-vous du contrôle » (**196866**) dans la section Véto ;
description de « Créneau d'intervention retenu » (196855) alignée sur le nouveau déclencheur (correspondance
déclarée, plus l'heure d'arrivée). Puis : « Montant à payer » (79230) passé en **entier** (le robot l'initialise),
et **retrait de toute mention d'horaires** (7 h 30 – 15 h 30) des libellés et descriptions — options de 196855,
descriptions de 107912, 196862, 79230. Puis : « Créneau d'intervention retenu » (196855) transformé en case
à cocher **« Imposer le tarif »**, nouveau « **Tarif imposé** » (**196867**) conditionné à la case ; « Heure de
rendez-vous du contrôle » (196866) remontée en tête de la section Véto, sa description dit qu'elle déclenche le
calcul du tarif et la demande de paiement. « Statut du paiement » (79233) sans « Réglé en régie ».

**Fait le 17/09 (retours du service)** : champs usager « Numéro LTA » (181905), « Numéro certificat » (132728),
« Vétérinaire Officiel » (132725), « Date signature certificat » (132727), « Nombre de colis » (188470)
supprimés ; recréés en **annotations** sous « Informations sur l'import » : « Numéro de LTA » (**196856**),
« Nombre de colis » (**196857**), « Numéro du certificat sanitaire » (**196858**), « Date du certificat
sanitaire » (**196859**), « Vétérinaire officiel signataire du certificat » (**196860**, liste + autre). Pièces
jointes LTA (192135) et certificat (132716) **facultatives**, regroupées sous le titre « Documents d'importation »
(181908) qui porte la consigne des 24 h. Annotation **« Créneau d'intervention retenu »** (**196855**, section
Véto). « Montant à payer » (79230) ramené à 6 500 / 12 500 F + autre. Listes de contrôle « Demande d'avis
vétérinaire » (78565), « Informations à vérifier » (78551) et le titre « CHECK TECHNICIEN » (76213) supprimés.
L'utilisateur a de son côté renommé les sections d'annotations (Instruction, Engagements, Véto, Régisseur),
créé « Responsable de l'entreprise » et retiré « Nom de l'entreprise ».

**Piège d'outillage (15/09)** : `lire_demarche` du MCP échoue tant que la plateforme n'expose pas le champ
`condition` (« Field 'condition' doesn't exist ») ; les écritures fonctionnent, et les identifiants se
relisent par `bin/rails runner` sur `MesDemarches::Queries::DemarcheRevision` (ids base64 `Champ-<stable_id>`).

**Effet sur les `stable_id` des préremplissages** (poste 2) : ceux de la démarche importateur sont désormais
stables pour les champs conservés ; ceux des démarches engagement et carnet restent à créer.

### 11.7 Conséquences

- Le poste 1 du devis (« conception des démarches, 1 j ») **tient** : on part d'une coquille existante, le
  nettoyage via MCP est de la configuration. Il monte si D3 (paiement) est confirmé.
- Les `stable_id` ci-dessus sont ceux du brouillon : les champs supprimés puis recréés en changeront, à
  relever une fois la révision stabilisée (poste 2, ids base64 des préremplissages).
