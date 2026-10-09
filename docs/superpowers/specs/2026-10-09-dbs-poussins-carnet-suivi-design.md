# Poussins d'un jour — Carnet de suivi de 21 jours (sous-projet 2/2)

- **Date** : 2026-10-09
- **Service** : Direction de la biosécurité (DBS), cellule zoosanitaire
- **Démarches** : **nouvelle démarche « carnet de suivi »** (à créer, numéro à venir), 3899 (demande de
  laissez-passer), 4038 (engagement / certificat d'isolement). Brouillons, non publiées.
- **Specs liées** : `2026-08-18-dbs-import-poussins-design.md` (spec mère : §1 point dur, §3.3, §5 relances et
  alerte), `2026-10-08-dbs-poussins-certificat-isolement-design.md` (sous-projet 1).
- **Prérequis plateforme** : `~/Rubymine/mes-demarches/docs/superpowers/specs/2026-10-09-formules-date-de-depot-recalcul-design.md`
  (§2 ci-dessous).
- **Sources** : `docs/dbs/import_volaille/Fiche de suivi.xlsx`, `Suivi de quarantaine.pdf` (p. 1 fiche de suivi,
  p. 2 levée d'isolement ; note manuscrite du service : « Démarche à part levée isolement ? Rattaché à la démarche
  certificat d'isolement »).

---

## 1. Principe

Chaque éleveur ayant déposé un engagement reçoit, à la délivrance du laissez-passer, un lien vers **son carnet** :
un dossier par éleveur et par lot, **rattaché à son engagement** (champ lien). Il le **dépose à J0** (accusé de
réception du lot), puis le tient chaque jour (morts du jour) en déposant ses modifications. Le robot surveille
(alerte de mortalité, relance des silences) et alimente le tableau de bord de la vétérinaire. La vétérinaire fait
une ou plusieurs **visites** ; chacune se conclut par une **décision** : prolongation (message), levée (acte +
acceptation) ou abattage (acte + refus).

```
LP accepté (visa) ──► dbs/inviter_carnets : un lien prérempli par engagement reçu (trace « Carnets envoyés »)
   engagement déposé plus tard ──► réécrit le LP ──► passage suivant : son lien part aussi (régularisation)
ÉLEVEUR : dépose le carnet à J0 (effectif reçu) ; puis saisit « Morts du jour N » et dépose ses modifications
ROBOT (rejeu quotidien) : alerte mortalité ; relance silence ; annotations du tableau de bord
VÉTÉRINAIRE : visite → compte rendu + Décision + visa
   Prolongation ──► message (compte rendu + total accordé) ; visa vidé ; dossier ouvert
   Levée        ──► suite administrative publipostée ──► dossier accepté
   Abattage     ──► suite administrative publipostée ──► dossier refusé (motivation)
```

**Motif réutilisable — « visite réutilisable »** (nouveau, 09/10) : un morceau de formulaire (compte rendu + décision
+ visa) utilisé autant de fois que nécessaire ; chaque usage est **figé par la décision qui le conclut** (message
dans la messagerie, ou document publiposté), puis le visa est vidé pour l'usage suivant. L'historique des
annotations de la plateforme en garde aussi la trace.

## 2. Prérequis plateforme (Mes-Démarches)

Le « Jour de suivi » est une formule publique `AUJOURDHUI() − J0`. Aujourd'hui, le recalcul nocturne des formules
datées ne touche, sur un dossier **déposé**, que les annotations privées (`Cron::RefreshClockDependentFormulasJob`) :
les formules publiques y sont figées au dépôt. Sans évolution, les jours ne s'afficheraient jamais.

Évolution demandée (spec Mes-Démarches séparée) :
1. `{Date de dépôt}` vaut la date du jour tant que le dossier n'est pas déposé ;
2. les formules publiques sont **recalculées à l'ouverture et au dépôt des modifications** par l'usager ;
3. les formules existantes qui veulent une valeur « au dépôt » (`AGE`, `AUJOURDHUI`, `EST_PASSEE`, `EST_FUTURE`,
   `MAINTENANT`) sont recensées et migrées vers `{Date de dépôt}` (ex. `ANNEES_ENTRE({Date de naissance}, {Date de dépôt})`).

Constat favorable : une modification d'un dossier déposé passe par un tampon validé par « Déposer les
modifications » (`submit_en_construction`), qui contrôle les champs **obligatoires visibles** — l'obligation des
jours échus fonctionne une fois le « Jour de suivi » à jour. Revers : le robot ne voit une saisie qu'après ce
dépôt ; les messages de relance le rappellent.

## 3. Décisions (09/10/2026)

| # | Décision | Alternative écartée |
|---|---|---|
| K1 | **Démarche carnet à part**, rattachée à l'engagement (champ lien) | Tout dans le dossier d'engagement (clos à la délivrance du certificat, engagements modifiables 21 jours) ; démarche « levée » séparée (4ᵉ dossier) |
| K2 | **Lien envoyé à chaque éleveur dont l'engagement est déposé**, certificat délivré ou non ; un engagement tardif reçoit son lien au passage suivant (régularisation) | Seuls les certificats délivrés (lot reçu sans suivi) ; tous les éleveurs de la liste (pas de rattachement à un engagement, localisation perdue) |
| K3 | **Le laissez-passer est le seul expéditeur** des liens (`dbs/inviter_carnets`, trace « Carnets envoyés ») : un engagement tardif réécrit déjà le LP, qui repasse en inspection | Deux expéditeurs (LP + engagement) ; signal posé sur l'engagement |
| K4 | **42 champs « Morts du jour N »** : 1-21 affichés si « Jour de suivi ≥ N », 22-42 si « Jour de suivi ≥ N » ET « Durée d'isolement ≥ N » | Bloc répétable « jours supplémentaires » (pas d'obligation, alerte plus complexe) |
| K5 | **Prolongation saisie par l'éleveur** (« Durée de prolongation », à la demande de la vétérinaire), car une condition ne peut s'appuyer que sur un champ usager placé avant ; **garde-fou** : le robot compare à la durée accordée (annotation) et prévient la vétérinaire en cas d'écart | Décision agent pilotant directement l'affichage (impossible : ni condition ni formule publique ne lisent une annotation) |
| K6 | **Décisions** : prolongation = **message** dans la messagerie (contient le **compte rendu**, trace officielle) ; levée = **acte publiposté + acceptation** ; abattage = **acte publiposté + refus** (mail de refus paramétrable, étiquette « refusé » acceptée) | Suite administrative pour la prolongation ; deux gabarits |
| K7 | **Acte minimal « façon laissez-passer »** : la décision seule, sans compte rendu ; un gabarit, texte de décision conditionnel (levée / abattage + motif) ; n° = « <carnet> / MPR / DBS / ZOO ». Une « lettre GEDA » pourra être demandée plus tard par la juriste | Acte + compte rendu ; lettre GEDA d'emblée |
| K8 | **Pas de courriel de fin de période** : la vétérinaire pilote depuis le **tableau des dossiers** (colonnes ci-dessous) ; elle est prévenue de l'arrivée des carnets par les notifications natives de la plateforme | Relance J21 + « lot mûr » par courriel à chaque éleveur |
| K9 | **Relance silence** à 4 jours vers l'éleveur | — |
| K10 | **Alerte de mortalité** le jour même à la cellule : morts du jour ≥ **3 %** de l'effectif restant la veille (paramètre) | Seuil cumulé ; base initiale |
| K11 | **Compte rendu de visite en zones de texte** (vaccins et traitements compris) | Bloc répétable (lourd pour la vétérinaire, compliqué à traiter) |

**Principe de conception (09/10)** : limiter le nombre de plugins spécifiques — chacun est une maintenance. Cette
version n'en ajoute que deux, `dbs/inviter_carnets` (dont le plan examinera s'il peut n'être qu'une configuration
de `dbs/inviter_eleveurs`) et `dbs/suivi_carnet` ; tout le reste est du YAML et des formules.

Hors périmètre de cette version : relance « carnet jamais ouvert » (la vétérinaire lit « Carnets envoyés ») ;
lettre GEDA ; SMS.

## 4. Démarche carnet — formulaire

**Préremplis par le lien** (non modifiables en pratique, relus par l'éleveur) :
- « Numéro du dossier d'engagement » (champ lien de dossier) — le rattachement ;
- « Nom de l'élevage », « Nom de l'éleveur » ;
- « Effectif attribué » ;
- « Date de début d'isolement (J0) » = date d'acceptation du laissez-passer.

**Accusé de réception (dépôt à J0)** : « Effectif reçu » (obligatoire, prérempli avec l'effectif attribué,
corrigeable : casse au transport).

**Suivi** :
- « Jour de suivi » (formule nombre) = `AUJOURDHUI() − J0` (prérequis §2) ;
- « Durée de prolongation (jours) » (nombre, facultatif, 0-21) — description : « À renseigner uniquement si la
  vétérinaire a prolongé l'isolement, avec la durée qu'elle vous a indiquée. » ;
- « Durée d'isolement » (formule) = `21 + {Durée de prolongation}` ;
- « Morts du jour 1 » … « Morts du jour 42 » (nombres entiers ≥ 0, obligatoires), conditions de K4 ;
- « Total des morts » (formule, somme), « Effectif restant » (formule, reçu − total).

**Annotations privées** :
- tableau de bord (§5.3) : « Jour de suivi (agent) » (formule, recalculée chaque nuit), « Dernier jour saisi »,
  « Mortalité sur 3 jours (%) », « Mortalité totale (%) » (formule) ;
- traces du robot : « Alertes mortalité » (jours signalés), « Relance silence » (dernier jour relancé),
  « Écart prolongation signalé » ;
- **visite réutilisable** : « Date de visite », « Agents », « Vaccins et traitements », « Niveau d'activité »,
  « Alimentation », « Présence de signes cliniques », « Autre » (zones de texte) ; « Décision » (Levée /
  Prolongation / Abattage) ; si Prolongation : « Prolongation totale (jours) » (total accordé depuis le début,
  0-21, description « saisissez le nouveau total, pas l'ajout »), « Prochaine visite » ; si Abattage :
  « Date d'abattage », « Motif » ; « Visa de la vétérinaire » (visa) ;
- « Suite administrative délivrée » (pièce jointe).

## 5. Robot

### 5.1 Côté laissez-passer (3899) — `dbs/inviter_carnets` (nouvelle tâche)

Active sur un laissez-passer **accepté**. Relit « Engagements reçus » (`Dbs::ListeEngagements`) ; pour chaque
engagement absent de la trace « Carnets envoyés » (nouvelle annotation texte, une ligne par envoi, format fixe
relisible), envoie à l'éleveur (courriel de la ligne) le lien prérempli vers le carnet (`PrefillURL`) : n° de
l'engagement, élevage et effectif (ligne de la liste des éleveurs, rapprochée par courriel — `Dbs::EleveursDuLot`),
J0 = date de traitement du laissez-passer. Écrit la trace **après chaque envoi** (comme `dbs/inviter_eleveurs`).
Les engagements tardifs (dépôt après acceptation) réécrivent « Engagements reçus », ce qui fait repasser le LP :
leur lien part au passage suivant.

### 5.2 Côté carnet — `dbs/suivi_carnet` (nouvelle tâche, unique bloc de la démarche)

À chaque passage (dépôt de modifications, rejeu quotidien) sur un carnet `en_construction` ou `en_instruction` :
- **Alerte de mortalité** : pour chaque jour N saisi absent de « Alertes mortalité », si
  `morts(N) ≥ seuil × (reçu − Σ morts(J < N))` → courriel à la cellule zoosanitaire (élevage, jour, morts,
  restant, lien du dossier), puis ajout de « JN » à l'annotation. Plusieurs alertes possibles, **une par jour**.
- **Relance silence** : soit D le dernier jour saisi (0 si aucun) ; si `jour courant − D ≥ 4` et D ≠ valeur de
  « Relance silence » → courriel à l'éleveur (jours à saisir, rappel « Déposer les modifications »), puis
  « Relance silence » = D. **Une relance par silence** : une nouvelle saisie change D.
- **Tableau de bord** : écrit « Dernier jour saisi » = D et « Mortalité sur 3 jours (%) » =
  morts des 3 derniers jours saisis ÷ effectif restant avant ces jours (paramètre `fenetre: 3`).
- **Garde-fou de prolongation** : si « Durée de prolongation » (usager) ≠ « Prolongation totale » (annotation)
  → courriel à la vétérinaire ; trace « Écart prolongation signalé » = la paire « saisi/accordé » signalée
  (pas de nouveau courriel tant que la paire ne change pas).
- **Rejeu quotidien** : un carnet silencieux n'est pas modifié, donc pas réinspecté ; la tâche **planifie son
  prochain passage au lendemain** : `ScheduledTask.enqueue(dossier, tâche, paramètres, date)`, exactement comme
  `payzen/payment_order` se replanifie lui-même (vérifié le 09/10 ; `ScheduledTaskJob` exécute les tâches échues
  chaque minute de 5 h à 23 h). Un rejeu ne connaît que les **paramètres enregistrés** à la planification : une
  modification du YAML ne s'applique qu'après une inspection normale du carnet. Arrêt de la replanification à la
  clôture du dossier (accepté / refusé).

Paramètres YAML : seuil (`0.03`), fenêtre (`3`), délai de silence (`4`), destinataires (cellule, vétérinaire),
textes des messages, libellés.

### 5.3 Côté carnet — chaîne de visite (YAML, un seul passage)

`conditional_field` sur « Visa de la vétérinaire » (non vide), puis sur « Décision » :
- **Prolongation** : message à l'éleveur (modèle du YAML : compte rendu complet — date, agents, vaccins et
  traitements, activité, alimentation, signes cliniques, autre —, durée accordée, cumul, prochaine visite,
  consigne « indiquez <Prolongation totale> dans Durée de prolongation »), puis `set_field` « Visa de la
  vétérinaire » = `""`. Dossier laissé ouvert. **Aucun cumul à calculer** : la vétérinaire saisit le **total**
  accordé (« Prolongation totale (jours) » : 10, puis 15), valeur absolue qu'elle écrase à chaque prolongation.
- **Levée** : `publipostage_v3` (acte, `champ_cible: Suite administrative délivrée`) → si la pièce est présente :
  `dossier_accepter`.
- **Abattage** : même acte (texte d'abattage, date et motif) → si présent : `dossier_refuser` avec motivation
  (« Abattage du lot ordonné le … — motif : … »).

`conditional_field` enchaîne sans intercepter les erreurs et relit le dossier après une tâche qui l'a modifié :
pas d'acceptation ni de refus sans acte.

## 6. Acte « Suite administrative »

Gabarit `models/dbs/poussins/Suite administrative.docx`, construit à partir du bloc « SUITE ADMINISTRATIVE » du
modèle de certificat, mis en page « façon laissez-passer » (en-tête officiel, références, décision, signature et
tampon), puis retouché par l'utilisateur dans Word (sa version devient la référence).

- N° « <carnet> / MPR / DBS / ZOO », « Faa'a, le <aujourd'hui> », « Dossier suivi par ».
- Références : certificat d'isolement (n° de l'engagement / MPR / DBS / ZOO, date de délivrance), laissez-passer.
- « Au vu du contrôle effectué le <date de visite> par <agents> » ; élevage, éleveur, lieu, effectif reçu, morts,
  restant.
- Décision conditionnelle (Sablon) : « Levée de l'isolement » **ou** « Abattage du lot le <date> — motif : <motif> ».
- Signataire et fonction : agent du visa (`calculs/email_to_names`), tampon, « Cachet ».

Contrôles avant chaque publication (leçons des gabarits précédents) : liste des `MERGEFIELD`, rendu de bout en bout
sur un vrai dossier **sans champ brut**, `proofErr` à retirer après un enregistrement Word, publication par `mc cp`
depuis `storage/` **après** déploiement du code dont le YAML dépend.

## 7. Tests

- `dbs/inviter_carnets` : un lien par engagement reçu non tracé ; trace écrite après chaque envoi ; engagement
  tardif invité au passage suivant ; rien sur un LP non accepté.
- `dbs/suivi_carnet` : alerte au seuil (égalité comprise), pas sous le seuil, une seule par jour, plusieurs jours
  distincts ; base « restant la veille » ; relance silence à 4 jours, pas deux fois pour le même silence, de
  nouveau après une nouvelle saisie puis un silence ; mortalité sur 3 jours ; garde-fou de prolongation ;
  planification du passage suivant.
- Chaîne de visite : prolongation (message avec le total, visa vidé) ; levée (acte puis acceptation) ; abattage (acte puis
  refus motivé) ; pas de clôture sans acte.
- Bout en bout : carnet de test rejoué sans rien envoyer ; rendu de l'acte sans champ brut.
