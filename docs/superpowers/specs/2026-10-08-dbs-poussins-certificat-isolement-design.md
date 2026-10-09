# Poussins d'un jour — Certificat d'isolement (sous-projet 1/2)

- **Date** : 2026-10-08
- **Service** : Direction de la biosécurité (DBS), cellule zoosanitaire
- **Démarches** : 4038 « Engagements pour recevoir des poussins d'un jour » (engagement de l'éleveur), 3899
  « Demande de laissez-passer » (importateur). Toutes deux en révision brouillon, **non publiées**.
- **Spec mère** : `2026-08-18-dbs-import-poussins-design.md`. Ce document **remplace** la mécanique du
  certificat décrite en §3.2 (certificat publiposté au visa du laissez-passer, annotation « Laissez-passer visé
  le » poussée vers les engagements) et la décision 12 de §7.
- **Sous-projet suivant** : le carnet de suivi de 21 jours (spec à venir), qui portera aussi les suites
  administratives (levée, prolongation, abattage).

---

## 1. Principe

**Le certificat d'isolement est l'engagement validé de l'éleveur.** Il est émis **avant** le laissez-passer,
qui le cite (référence 6/) :

```
ÉLEVEUR : dépôt de l'engagement (démarche 4038)
   ▼  l'agent relit et pose son VISA sur l'engagement
ROBOT (un seul passage) : génère le CERTIFICAT dans l'engagement → accepte l'engagement
   │                       (le mail d'acceptation donne le lien vers le certificat)
   ▼  passage suivant : la ligne de l'engagement sur le laissez-passer devient « … — certificat délivré le J »
VÉTÉRINAIRE : vise le laissez-passer quand elle le juge bon → LP généré, cite les certificats délivrés
```

**Pourquoi** (correction du 08/10) : le laissez-passer cite les certificats d'isolement ; faire dépendre le
certificat du visa du laissez-passer créait une dépendance circulaire. Logiquement, l'éleveur s'engage à isoler
les poussins *avant* que le lot ne soit autorisé à entrer.

## 2. Décisions (08/10/2026)

| # | Décision | Alternative écartée |
|---|---|---|
| C1 | Certificat **rangé dans le dossier d'engagement**, puis **engagement accepté** par le robot : le mail d'acceptation porte le lien | Envoi par messagerie (dossier laissé ouvert) ; envoi à l'importateur |
| C2 | Déclenché par une **validation humaine** : un **visa** « Visa de l'agent habilité » sur l'engagement | Émission automatique au dépôt (aucune relecture d'un acte signé) — à reconsidérer après le terrain |
| C3 | **Signataire = agent du visa**, avec sa **fonction** (table des agents) à la place du texte figé « vétérinaire officielle » | Nom fixe dans le modèle |
| C4 | Case « Détenteur — signature lu et approuvé » remplacée par la **mention de l'engagement souscrit sur Mes-Démarches** (date de dépôt, n° de dossier) | Signature manuscrite sur place |
| C5 | Gabarit = **première partie** du modèle papier ; « Signature et cachet » → **« Cachet »**, avec le **tampon** repris du laissez-passer | Suites administratives sur le même document (→ carnet) |
| C6 | Les lignes **« Date / Numéro du certificat sanitaire » sont retirées** : donnée tardive, sans incidence sur l'engagement d'isoler ; elle figure sur le laissez-passer | Lignes vides ; validation bloquée tant qu'elles manquent |
| C7 | Le certificat **peut citer la demande de laissez-passer** (« demande n° X du Y ») : c'est une référence usager, pas le document émis | Aucune référence à la demande |
| C8 | **Pas de blocage du laissez-passer** : la vétérinaire vise quand elle le juge bon, même si des certificats manquent (engagement papier, éleveur injoignable). La référence 6/ cite les certificats **délivrés** à ce moment | Robot qui refuse de générer le LP tant qu'un certificat manque |

Hors périmètre, à rouvrir selon le terrain : ajout manuel d'un engagement fait sur papier ; émission
automatique au dépôt ; date de levée d'isolement (→ carnet).

## 3. Démarche 4038 — modifications

| Élément | Action |
|---|---|
| « Visa de l'agent habilité » (visa) | **Ajouté**, section Instruction ; mêmes personnes habilitées que le visa de la 3899 |
| « Certificat d'isolement délivré » (pièce jointe) | **Ajoutée**, section « Suivi robot » |
| « Laissez-passer visé le » (197028) | **Supprimée** (mécanique abandonnée) |
| « Certificat d'isolement établi le » (197030) | **Supprimée** (doublon de la date d'acceptation) |
| « Date de levée d'isolement prévue » (197032) | **Conservée, non remplie** : calcul reporté au carnet (base = date d'arrivée, plus le visa) |

## 4. Robot

### 4.1 Côté engagement (bloc `dbs_poussins_engagement`)

Nouvelle chaîne, sur le modèle de la délivrance du laissez-passer (un seul passage ; `conditional_field`
n'intercepte pas les erreurs et relit le dossier après une tâche qui l'a modifié) :

```yaml
- conditional_field:                          # engagement en construction ou en instruction
    champ: Visa de l'agent habilité
    valeurs:
      "":
      par défaut:
        - publipostage_v3:                    # certificat → annotation « Certificat d'isolement délivré »
        - conditional_field:                  # présent ⇒ accepter
            champ: Certificat d'isolement délivré
            valeurs: { "": , par défaut: [ dossier_accepter ] }
```

La tâche existante `dbs/engagement_recu` continue de tourner sur les états
`en_construction, en_instruction, accepte`.

### 4.2 « Certificat délivré » sur le laissez-passer

`dbs/engagement_recu` réécrit déjà la ligne de l'engagement dans « Engagements reçus » du laissez-passer.
**Elle y ajoute la date de délivrance** quand l'engagement est **accepté** (date de traitement du dossier) :

```
Nom (courriel) — dossier N — déposé le J [— non attendu] [— certificat délivré le J2]
```

L'acceptation modifie l'engagement, qui repasse en inspection : la ligne est mise à jour au passage suivant.
`Dbs::ListeEngagements` lit et écrit ce suffixe (format et lecture restent inverses l'un de l'autre ; une
ligne sans suffixe reste lisible).

### 4.3 Côté laissez-passer

Seule la référence 6/ change : `dbs/references_laissez_passer` ne cite que les engagements portant
« certificat délivré », avec la date de délivrance (« Certificat d'isolement n° N/MPR/DBS/ZOO du J2 sur le site
d'élevage … »).

### 4.4 Lecture de la demande liée — sans code

Le robot traverse déjà un champ lien de dossier : un nom de champ **pointé** (`object_field_values`,
`field_checker.rb`) lit l'en-tête, les champs **et** les annotations du dossier lié, chargés par la requête
GraphQL (même mécanisme que la recopie 3190 → 3604 de la Diren). Les données du lot sont donc de simples
colonnes du YAML de la publipostage, préfixées par le champ lien « Numéro du dossier de laissez-passer » (197027) :

| Donnée du certificat | Chemin |
|---|---|
| N° de la demande | `Numéro du dossier de laissez-passer.number` |
| Date de dépôt de la demande | `Numéro du dossier de laissez-passer.date_depot` (texte « JJ/MM/AAAA à HHhMM » : jour seul à obtenir, cf. plan) |
| Adresse de l'importateur | `Numéro du dossier de laissez-passer.demandeur…` (adresse de l'établissement, cf. plan) |
| Permis | `Numéro du dossier de laissez-passer.Numéro de permis d'importation préalable` |
| Lot total | `Numéro du dossier de laissez-passer.Quantité totale` |
| Expéditeur | `Numéro du dossier de laissez-passer.Expéditeur sur le laissez-passer` |
| Pays d'origine | `Numéro du dossier de laissez-passer.Pays d'origine` — **nouvelle annotation formule sur la 3899** : `SI({Provenance} == "Autre pays", {Pays de provenance}, {Provenance})` |

Signataire et « Dossier suivi par » : `calculs/email_to_names` (existant) sur **l'engagement** — visa de
l'engagement et son dernier instructeur, résolus par la table `dbs_poussins_agents`.

Lus directement dans l'engagement : n° du dossier, date de dépôt, importateur, date d'arrivée, vol, effectif
attribué, nom de l'éleveur, entreprise (établissement), commune ou île.

**Adresse du lieu d'isolement** : le champ carte Te Fenua (197045) n'est pas lisible aujourd'hui par le robot
(`champ_value` rend `TeFenuaChamp`). Le plan vérifie ce que l'API expose (adresse texte du point) ; à défaut,
le certificat imprime la **commune ou île** (197044).

### 4.5 Sécurités

- Demande liée absente : les données du lot sortent vides — c'est l'agent qui vise l'engagement après relecture
  (le lien est prérempli par l'invitation et obligatoire). Pas de contrôle codé.
- Engagement refusé ou classé sans suite : la chaîne ne tourne pas (états `en_construction, en_instruction`).
- Engagement accepté : plus de régénération du certificat (la publipostage ne traite pas l'état `accepte`).
- Certificat absent après la génération : pas d'acceptation (contrôle dans la chaîne).

## 5. Gabarit `models/dbs/poussins/Certificat d'isolement.docx`

Construit par script à partir de la **première partie** de `Certificat d'isolement poussin d'un jour et suite
administrative doc vierge .docx` (vrais `MERGEFIELD`, anciens champs `DocRef`, `Prop_Pays`, `AnimalNumID`
purgés), puis **retouché par l'utilisateur dans Word** — la version retouchée devient la référence.

- En-tête : « N° <engagement> / MPR / DBS / ZOO », « Faa'a, le <aujourd'hui> », « Dossier suivi par ».
- « Je soussigné(e), <prénom NOM>, <fonction> de la cellule zoosanitaire de la direction de la biosécurité,
  certifie avoir mis en isolement les poussins d'un jour, originaires de <pays>, du lot décrit ci-dessous. »
- Lot : date d'arrivée, moyen de transport (vol), importateur et son adresse, permis, lot total, expéditeur,
  « Demande de laissez-passer n° X du Y ». **Pas** de certificat sanitaire.
- Élevage : nombre de poussins mis à l'isolement, établissement, « appartenant à », adresse du lieu
  d'isolement.
- Motifs et textes réglementaires : inchangés.
- Bas : « Engagements souscrits par le détenteur sur Mes-Démarches le <dépôt> (dossier n° <engagement>) » ;
  **tampon** (image reprise du gabarit du laissez-passer) et **« Cachet »** ; fonction du signataire à la place
  de « Vétérinaire officielle ».

Contrôles avant chaque publication (leçons du laissez-passer) : liste complète des `MERGEFIELD`, rendu de bout
en bout sur un vrai dossier **sans aucun champ brut** dans le PDF, publication par `mc cp` depuis `storage/`.

## 6. Tests

- `Dbs::ListeEngagements` : format/lecture du suffixe « certificat délivré le J », compatibilité des lignes
  existantes, ordre avec « non attendu ».
- `Dbs::EngagementRecu` : date de délivrance posée quand l'engagement est accepté, absente sinon.
- `Dbs::ReferencesLaissezPasser` : la référence 6/ ne cite que les certificats délivrés.
- Bout en bout : rejouer la publipostage du certificat sur l'engagement 683297 (lié à 683290) en `rails runner`,
  sans rien envoyer, et relire le PDF.
