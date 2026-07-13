# Configuration robot de la justification Diren (3604) : recopie depuis la 3190 + relance bilan

**Date** : 2026-07-13
**Statut** : validé (approche A)

## Contexte

La démarche 3604 « Subvention Diren / Justification des dépenses » référence, via le champ
DossierLink « Dossier de demande de subvention », un dossier de la démarche 3190
« Appel à projets de la DIREN ». Pour que l'agent instruise la justification sans ouvrir
le dossier source, on recopie automatiquement les informations d'octroi dans les
annotations privées de la 3604. La configuration porte aussi une relance usager pour le
bilan moral et financier, déclenchée par l'agent via une case à cocher.

## Mapping

| Annotation 3604 (destination) | Source 3190 (annotation, section CASE) |
|---|---|
| Montant accordé (IntegerNumber) | Montant octroyé (IntegerNumber) |
| Postes de dépenses éligibles (Textarea) | Dépenses retenues (Textarea) |

La formule « Montant restant à justifier » de la 3604 (Montant accordé − Montant des
dépenses justifiées) se recalcule automatiquement côté mes-démarches une fois
« Montant accordé » renseigné.

## Approche retenue

Configuration pure (aucun code Ruby) : nouveau fichier
`storage/configurations/diren_justification.yml`.

- Le templating de `set_annotation` traverse les DossierLink :
  `{Dossier de demande de subvention.Montant octroyé}` lit l'annotation dans le dossier
  lié (`object_field_values`, field_checker.rb).
- Chaque recopie est enveloppée dans un `conditional_field` sur la valeur source :
  si elle est vide (CASE pas encore passée, dossier lié absent ou erroné), on ne fait rien.
  **Garde-fou indispensable** : sans lui, `set_annotation` écrirait une valeur vide,
  soit `0` dans « Montant accordé » ; comme `set_annotation` ne réécrit jamais une
  annotation déjà remplie, ce `0` bloquerait définitivement la vraie valeur.
- Un contrôle `dossier_link_check` vérifie que le dossier saisi appartient bien à la 3190
  et demande correction à l'usager sinon.

Approches écartées : `set_annotation` sans garde (risque du `0` définitif) ; nouveau
FieldChecker générique « copie dossier lié → annotations » (réutilisable mais code +
tests + déploiement pour un besoin déjà couvert — à reconsidérer si le pattern se
multiplie, cf. chantier coordination subventions).

## Relance bilan moral et financier

L'annotation privée checkbox « Envoyer la demande de bilan » (3604) est cochée par
l'agent quand, sur la tranche 2, tous les justificatifs sont validés et qu'il ne manque
plus que le bilan moral et financier. Le robot envoie alors un message à l'usager via la
messagerie du dossier :

- `conditional_field` sur « Envoyer la demande de bilan » (case cochée → valeur « Oui »),
  état `en_instruction` uniquement.
- `daf/message` sans `destinataires` → message usager via la messagerie, avec
  anti-doublon intégré (`check_not_sent` : un texte identique n'est jamais renvoyé sur
  le même dossier). L'agent peut donc décocher/recocher sans provoquer de doublon.
- L'annotation YesNo « Bilan moral et financier fourni » initialement envisagée a été
  remplacée par cette checkbox : une YesNo non renseignée est lue « Non » par le
  framework, ce qui aurait déclenché la relance sur des dossiers non évalués.
- Évolution prévue : ajouter plus tard au message un lien de téléchargement du modèle
  de bilan (l'usager n'a plus accès au formulaire une fois le dossier en instruction).
  Attention : changer le texte du message fera repartir un envoi sur les dossiers ayant
  reçu l'ancienne version (anti-doublon par comparaison du texte exact).

## Configuration

```yaml
par_defaut: &par_defaut
  email_instructeur: robot-mes-demarches@admnistration.gov.pf
  messages_automatiques: false
  pieces_messages:
    # prélude standard (repris de diren_controle.yml)

justification:
  <<: *par_defaut
  demarches: [ 3604 ]
  controles:
    - dossier_link_check:
        champ: Dossier de demande de subvention
        demarches: [ 3190 ]
        message_mauvaise_demarche: >-
          Le numéro de dossier indiqué ne correspond pas à un dossier d'appel à projets
          de la DIREN. Vérifiez le numéro de votre demande de subvention.
  when_ok:
    - conditional_field:
        etat_du_dossier: [ en_construction, en_instruction ]
        champ: Dossier de demande de subvention.Montant octroyé
        valeurs:
          "":                    # source vide → on attend le prochain passage
          par défaut:
            - set_annotation:
                annotation: Montant accordé
                valeur: "{Dossier de demande de subvention.Montant octroyé}"
    - conditional_field:
        etat_du_dossier: [ en_construction, en_instruction ]
        champ: Dossier de demande de subvention.Dépenses retenues
        valeurs:
          "":
          par défaut:
            - set_annotation:
                annotation: Postes de dépenses éligibles
                valeur: "{Dossier de demande de subvention.Dépenses retenues}"
    - conditional_field:
        etat_du_dossier: [ en_instruction ]
        champ: Envoyer la demande de bilan
        valeurs:
          "Oui":
            - daf/message:
                message: |
                  Bonjour,

                  L'ensemble des justificatifs de dépenses de votre dossier a été validé.
                  Il ne manque plus que le bilan moral et financier de votre projet pour
                  clore votre dossier.

                  Merci de nous le transmettre en réponse à ce message, en pièce jointe
                  via la messagerie de votre dossier.

                  Cordialement,
                  La Direction de l'environnement
          par défaut:
```

## Comportement

- Déclenchement à chaque vérification du dossier 3604 en `en_construction` ou
  `en_instruction` (dépôt, modification, passage en instruction).
- Recopie effective au premier passage où la source est renseignée ; les passages
  suivants ne réécrivent pas (log « already contains value ») — la saisie agent est protégée.
- Si la CASE corrige le montant après recopie, la 3604 n'est pas mise à jour
  automatiquement (limitation assumée de `set_annotation`).
- `messages_automatiques: false` : pas de mail automatique à l'usager ; le
  `dossier_link_check` alimente néanmoins le rapport d'anomalies si le numéro de
  dossier est erroné.

## Validation

1. Syntaxe : `ruby -ryaml -e "YAML.load_file('storage/configurations/diren_justification.yml', aliases: true)"`.
2. Test local sur un dossier 3604 réel lié à un dossier 3190 dont la CASE a statué :
   vérifier les deux annotations puis le recalcul de « Montant restant à justifier ».
3. Contre-tests : dossier 3190 sans montant octroyé (aucune écriture), numéro de
   dossier d'une autre démarche (message d'anomalie).
4. Relance bilan : cocher « Envoyer la demande de bilan » sur un dossier en instruction
   → message posté dans la messagerie ; relancer la vérification → pas de doublon ;
   case décochée → aucun envoi.
5. Déploiement : copie dans `robot-mes-demarches-staging` + `mirror_staging.sh`,
   vérification, puis production (`robot-mes-demarches-production` + `mirror_production.sh`).
