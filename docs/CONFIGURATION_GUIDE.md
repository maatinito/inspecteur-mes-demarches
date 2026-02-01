# Guide de Configuration YAML

Ce guide explique comment écrire des fichiers de configuration YAML pour l'auto-instructeur Mes-Démarches.

## Table des matières

1. [Vue d'ensemble](#vue-densemble)
2. [Structure d'un fichier de configuration](#structure-dun-fichier-de-configuration)
3. [Syntaxe YAML de base](#syntaxe-yaml-de-base)
4. [FieldCheckers disponibles](#fieldcheckers-disponibles)
5. [Patterns courants](#patterns-courants)
6. [Exemples commentés](#exemples-commentés)
7. [Pièges à éviter](#pièges-à-éviter)

## Vue d'ensemble

Les fichiers de configuration YAML définissent les actions automatiques à effectuer sur les dossiers Mes-Démarches. Chaque configuration cible une ou plusieurs démarches et définit :

- Des **contrôles** à effectuer (validation de champs, vérification de pièces jointes, etc.)
- Des **actions** à déclencher quand tout est OK (`when_ok`)
- Des **messages** à envoyer en cas d'anomalie ou de succès

Les fichiers sont placés dans `storage/configurations/` et chargés par `VerificationService`.

## Conventions de fichiers

### Extension de fichier

**IMPORTANT** : Les fichiers de configuration doivent obligatoirement avoir l'extension **`.yml`**.

❌ **Incorrect** : `ma_config.yaml`
✅ **Correct** : `ma_config.yml`

Le système de chargement (`Tools::DiskFileManager`) recherche uniquement les fichiers `*.yml` dans le répertoire `storage/configurations/`. Les fichiers `.yaml` ne seront pas chargés.

### Nommage des fichiers

Utilisez des noms descriptifs en snake_case qui reflètent la démarche ou le service concerné :
- `dgae_investissement.yml`
- `dca_permis_de_construire.yml`
- `diren_prises_de_son.yml`

## Structure d'un fichier de configuration

### Structure recommandée

La plupart des fichiers de configuration suivent cette structure standard :

```yaml
# 1. Bloc par_defaut (RECOMMANDÉ)
par_defaut: &par_defaut
  email_instructeur: service@administration.gov.pf
  messages_automatiques: false
  pieces_messages:
    debut_premier_mail: "Bonjour..."
    debut_second_mail: "Bonjour..."
    entete_anomalies: "Les points suivants doivent être résolus:"
    entete_anomalie: "Il n'y a qu'un seul point à résoudre:"
    tout_va_bien: "Toutes les vérifications se sont bien passées."
    fin_anomalie: |
      <b>Important</b>: Ne donnez pas de corrections via la messagerie.
      Effectuez les corrections en <b>modifiant directement le dossier</b>.
    fin_mail: "Cordialement.<br>Le service"

# 2. Blocs de messages réutilisables (optionnel)
messages:
  mon_message: &mon_message |
    Bonjour,
    Votre dossier est prêt.
    Cordialement.

# 3. Point d'entrée - Configuration principale
ma_configuration:
  <<: *par_defaut                      # Hérite du bloc par_defaut
  demarches: [1234, 5678]              # IDs des démarches (OBLIGATOIRE)
  etat_du_dossier: [en_construction]   # États du dossier (optionnel)
  controles:                           # Liste des contrôles (peut être vide)
  messages_automatiques: false         # Peut surcharger la valeur de par_defaut
  when_ok:                             # Actions si tous les contrôles passent
    - action_1:
        param1: valeur1
```

### Le bloc `par_defaut`

Le bloc `par_defaut` est **fortement recommandé** car il permet de :
- Centraliser les paramètres communs (email instructeur, messages)
- Éviter la duplication de code
- Faciliter la maintenance

**Éléments typiques du bloc `par_defaut` :**

| Paramètre | Type | Description |
|-----------|------|-------------|
| `email_instructeur` | String | Email de l'instructeur robot (ex: `robot-mes-demarches@administration.gov.pf`) |
| `messages_automatiques` | Boolean | Active/désactive l'envoi automatique de messages aux usagers |
| `pieces_messages` | Hash | Messages standards pour les notifications automatiques |

**Les `pieces_messages` standards :**

| Clé | Usage |
|-----|-------|
| `debut_premier_mail` | Début du premier message envoyé |
| `debut_second_mail` | Début des messages suivants |
| `entete_anomalies` | En-tête quand plusieurs anomalies |
| `entete_anomalie` | En-tête quand une seule anomalie |
| `tout_va_bien` | Message quand tout est OK |
| `fin_anomalie` | Pied de page des messages d'anomalie |
| `fin_mail` | Signature du message |

### Structure minimale (sans par_defaut)

Si vous n'utilisez pas de bloc `par_defaut`, la structure minimale est :

```yaml
# Bloc de configuration par défaut (optionnel)
par_defaut: &par_defaut
  email_instructeur: email@example.com
  messages_automatiques: true
  pieces_messages:
    debut_premier_mail: "Bonjour..."
    entete_anomalies: "Les points suivants doivent être résolus:"
    # ... autres messages

# Bloc de messages réutilisables (optionnel)
messages:
  mon_message: &mon_message |
    Bonjour,
    Votre dossier est prêt.
    Cordialement.

# POINT D'ENTRÉE : Configuration principale
ma_configuration:
  <<: *par_defaut                      # Hérite des paramètres par défaut
  demarches: [1234, 5678]              # IDs des démarches concernées (OBLIGATOIRE)
  etat_du_dossier: [en_construction]   # États du dossier à traiter (optionnel)

  controles:                           # Liste des contrôles à effectuer
    - field_checker_1:
        param1: valeur1
    - field_checker_2:
        param2: valeur2

  when_ok:                             # Actions si tous les contrôles passent
    - action_1:
        param1: valeur1
    - conditional_field:               # Action conditionnelle
        champ: "Nom du champ"
        valeurs:
          "valeur_specifique":
            - action_2:
                param: valeur
          par défaut:
```

### Points clés

- **Point d'entrée** : Seuls les blocs avec l'attribut `demarches` sont exécutés
- **Templates** : Les blocs sans `demarches` sont des templates réutilisables (avec `&anchor`)
- **Héritage** : Utiliser `<<: *anchor` pour hériter d'un template

## Syntaxe YAML de base

### Anchors et Aliases

```yaml
# Définir une ancre (&)
template: &mon_template
  param1: valeur1
  param2: valeur2

# Réutiliser une ancre (*)
config1:
  <<: *mon_template    # Hérite de tous les paramètres
  param3: valeur3      # Ajoute un paramètre supplémentaire

config2:
  action: *mon_template  # Référence directe au template
```

### Merge Keys (`<<:`)

```yaml
# Fusion de plusieurs templates
config:
  <<: *template1
  <<: *template2
  param_perso: valeur
```

### Multilignes

```yaml
# Bloc littéral (conserve les retours à la ligne)
message: |
  Ligne 1
  Ligne 2
  Ligne 3

# Bloc replié (remplace les retours à la ligne par des espaces)
description: >
  Texte long qui sera
  sur une seule ligne.
```

## FieldCheckers disponibles

Pour connaître les paramètres d'un FieldChecker, regarder sa classe dans `app/lib/` :

```ruby
class MonChecker < FieldChecker
  def required_fields
    super + %i[param_obligatoire autre_param]
  end

  def authorized_fields
    super + %i[param_optionnel]
  end
end
```

### Liste des FieldCheckers principaux

| Checker | Description | Paramètres requis | Paramètres optionnels |
|---------|-------------|-------------------|----------------------|
| `conditional_field` | Action conditionnelle basée sur la valeur d'un champ | `champ`, `valeurs` | `etat_du_dossier` |
| `publipostage` / `publipostage_v2` / `publipostage_v3` | Génération de documents Word | `modele`, `champ_cible`, `champs` | `type_de_document`, `nom_fichier`, `calculs`, `etat_du_dossier` |
| `daf/message` | Envoi de message ou email | `message` | `destinataires`, `champ_envoi` |
| `set_field` | Modification d'une annotation | `champ`, `valeur` | `si_vide`, `decalage` |
| `daf/copy_order` | Copie de blocs répétables de champs vers annotations | `champ_source`, `bloc_destination`, `champs_destination` | `etat_du_dossier` |

### Trouver les paramètres d'un checker

1. Ouvrir le fichier de la classe (ex: `app/lib/daf/message.rb`)
2. Regarder `required_fields` : paramètres obligatoires
3. Regarder `authorized_fields` : paramètres optionnels

Exemple :
```ruby
# app/lib/daf/message.rb
def required_fields
  super + %i[message]  # 'message' est obligatoire
end

def authorized_fields
  super + %i[destinataires champ_envoi]  # 'destinataires' et 'champ_envoi' sont optionnels
end
```

## Patterns courants

### 1. Conditional Field

Execute des actions basées sur la valeur d'un champ :

```yaml
when_ok:
  - conditional_field:
      champ: "Statut du dossier"
      valeurs:
        "Accepté":
          - action_1:
              param: valeur1
        "Refusé":
          - action_2:
              param: valeur2
        "":                    # Valeur vide
          - action_3:
              param: valeur3
        par défaut:            # Toutes les autres valeurs
          - action_4:
              param: valeur4
```

**Important** : Les valeurs sont des chaînes de caractères. Pour les cases à cocher :
- `"true"` ou `"Oui"` pour coché
- `"false"` ou `""` pour non coché

### 2. Conditional Field imbriqué

On peut imbriquer les `conditional_field` :

```yaml
- conditional_field:
    champ: "Type de demande"
    valeurs:
      "Permis de construire":
        - conditional_field:
            champ: "Signataire désigné"
            valeurs:
              "Oui":
                - daf/message:
                    destinataires: "{Email du signataire}"
                    message: "Votre signature est requise."
              par défaut:
      par défaut:
```

### 3. Set Field avec condition

Remplir automatiquement un champ si vide :

```yaml
- conditional_field:
    champ: "Date limite"
    valeurs:
      "":                      # Si le champ est vide
        - set_field:
            si_vide: oui       # Ne modifie que si vide
            champ: "Date limite"
            valeur: "{date_depot}"
            decalage:
              jours: 15        # Ajoute 15 jours à la date
      par défaut:              # Si le champ est déjà rempli, ne rien faire
```

### 4. Publipostage avec template réutilisable

```yaml
# Template de base
entete_publipostage: &entete_standard
  type_de_document: docx
  etat_du_dossier: [en_construction, en_instruction]
  calculs:
    - calculs/email_to_names:
        mails: &mail_names
          william.joseph: William,Joseph,Tourneur de tête
          clautier: Christian,Lautier,Simplifier le monde
  champs: &champs_standard
    - colonne: Dossier
      champ: number
    - colonne: Nom
      champ: demandeur.nom
    - colonne: Prénom
      champ: demandeur.prenom
    - Demandeur
    - Commune postale

# Utilisation du template
ma_config:
  demarches: [1234]
  when_ok:
    - publipostage_v3:
        <<: *entete_standard
        champ_cible: Proposition de permis
        modele: 'dca/pc/modèle permis.docx'
        nom_fichier: Permis {number} {horodatage}
```

### 5. Envoi de message avec variables

```yaml
messages:
  notification_signature: &notif_sig |
    Bonjour,
    Le permis n°{number} pour {Demandeur} est prêt.
    Merci de procéder à la signature.
    Cordialement,
    Direction

ma_config:
  demarches: [1234]
  when_ok:
    - conditional_field:
        champ: "Notifier le signataire"
        valeurs:
          "true":
            - daf/message:
                destinataires: "{Signataire du permis}"  # Email dynamique depuis le dossier
                champ_envoi: "Date notification"         # Annotation pour éviter les doublons
                message: *notif_sig
          par défaut:
```

**Variables disponibles** :
- `{number}` : Numéro du dossier
- `{date_depot}` : Date de dépôt
- `{date_passage_en_instruction}` : Date de passage en instruction
- `{Nom du champ}` : Valeur d'un champ ou annotation du dossier
- `{demandeur.nom}`, `{demandeur.prenom}`, `{demandeur.email}` : Infos du demandeur
- `{horodatage}` : Timestamp actuel

### 6. Copie de blocs répétables (daf/copy_order)

Copie automatique des données d'un bloc répétable (champs) vers un bloc répétable (annotations) :

```yaml
ma_config:
  demarches: [3508]
  when_ok:
    # Copie simple : tous les champs avec le même nom
    - daf/copy_order:
        champ_source: "Investisseur(s) personne physique"
        bloc_destination: "Investisseur personne physique"
        champs_destination:
          "Civilité de l'investisseur": "Civilité de l'investisseur"
          "Prénom de l'investisseur": "Prénom de l'investisseur"
          "Nom de l'investisseur": "Nom de l'investisseur"

    # Copie avec mapping différent et templates
    - daf/copy_order:
        champ_source: "Commandes"
        bloc_destination: "Bons de commande"
        champs_destination:
          "Référence": "Numéro commande"           # Mapping simple
          "Client": "{Nom} {Prénom}"                # Template avec plusieurs champs
          "Total": "{Montant HT} F CFP"             # Template avec texte
```

**Copie conditionnelle selon un champ** :

```yaml
when_ok:
  - conditional_field:
      champ: "Type de déclarant"
      valeurs:
        "Personne morale":
          - daf/copy_order:
              champ_source: "Représentant légal de la personne morale"
              bloc_destination: "Représentant légal"
              champs_destination:
                "Civilité du représentant": "Civilité du représentant légal"
                "Nom du représentant": "Nom du représentant légal"
        "Personne physique":
          - daf/copy_order:
              champ_source: "Investisseur(s) personne physique"
              bloc_destination: "Investisseur personne physique"
              champs_destination:
                "Civilité": "Civilité de l'investisseur"
                "Nom": "Nom de l'investisseur"
        par défaut:
```

**Points importants** :
- Les noms de champs sont sensibles à la casse et aux espaces
- Supporte les templates avec syntaxe `{champ}`
- Peut copier des champs texte et des pièces justificatives
- Crée automatiquement le bon nombre de lignes dans le bloc destination

## Exemples commentés

### Exemple 1 : Génération automatique de permis

```yaml
pc:
  demarches: [3194]
  etat_du_dossier: [en_instruction]
  email_instructeur: service@example.com

  when_ok:
    # Remplir automatiquement le nom du demandeur si vide
    - conditional_field:
        champ: Demandeur
        valeurs:
          "":
            - conditional_field:
                champ: Numéro TAHITI
                valeurs:
                  "":
                    # Personne physique
                    - set_field:
                        si_vide: oui
                        champ: "Demandeur"
                        valeur: "{demandeur.prenom} {demandeur.nom}"
                  par défaut:
                    # Personne morale
                    - set_field:
                        si_vide: oui
                        champ: "Demandeur"
                        valeur: "{Numéro TAHITI} {Numéro TAHITI.etablissement.entreprise.raison_sociale}"
          par défaut:

    # Générer le permis en mode automatique
    - conditional_field:
        champ: Mode de production du permis
        valeurs:
          "automatique":
            - publipostage_v3:
                champ_cible: Proposition de permis
                type_de_document: docx
                modele: 'dca/pc/modèle permis.docx'
                nom_fichier: Permis de construire {number} {horodatage}
                champs:
                  - colonne: Dossier
                    champ: number
                  - colonne: Nom déclarant
                    champ: demandeur.nom
                  - colonne: Prénom déclarant
                    champ: demandeur.prenom
                  - Demandeur
                  - Parcelle concernée
                  - Réserves
          par défaut:

    # Générer le PDF final si demandé
    - conditional_field:
        champ: Générer le permis de construire
        valeurs:
          "Oui":
            - publipostage_v2:
                champ_cible: Permis de construire
                type_de_document: pdf
                modele: 'dca/pc/modèle permis.docx'
                nom_fichier: Permis de construire {number}
                champs:
                  - colonne: Dossier
                    champ: number
                  - Demandeur
          par défaut:
```

### Exemple 2 : Workflow de notification

```yaml
messages:
  demande_pieces: &msg_pieces |
    Bonjour,
    Des pièces complémentaires sont nécessaires pour traiter votre dossier.
    Merci de les déposer dans les meilleurs délais.
    Cordialement.

  validation_dossier: &msg_validation |
    Bonjour,
    Votre dossier a été validé et est maintenant en cours d'instruction.
    Cordialement.

workflow:
  demarches: [1234]
  email_instructeur: agent@example.com
  messages_automatiques: true

  controles:
    # Vérifier que toutes les pièces sont présentes
    - check_piece:
        libelle: "Pièce d'identité"
        message: "La pièce d'identité est manquante."
    - check_piece:
        libelle: "Justificatif de domicile"
        message: "Le justificatif de domicile est manquant."

  when_ok:
    # Définir la date limite si vide
    - conditional_field:
        etat_du_dossier: en_construction
        champ: "Date limite reception"
        valeurs:
          "":
            - set_field:
                si_vide: oui
                champ: "Date limite reception"
                valeur: "{date_depot}"
                decalage:
                  jours: 15
          par défaut:

    # Notifier l'usager que le dossier est complet
    - conditional_field:
        etat_du_dossier: en_construction
        champ: "Notification envoyée"
        valeurs:
          "":
            - daf/message:
                message: *msg_validation
                champ_envoi: "Notification envoyée"
          par défaut:
```

## Pièges à éviter

### 1. Oublier `demarches`

❌ **Incorrect** : Ce bloc ne sera jamais exécuté
```yaml
ma_config:
  email_instructeur: test@example.com
  controles: [...]
```

✅ **Correct** :
```yaml
ma_config:
  demarches: [1234]
  email_instructeur: test@example.com
  controles: [...]
```

### 2. Confusion entre templates et points d'entrée

❌ **Incorrect** : Demander `etat_du_dossier` dans un template
```yaml
template_publipostage: &template
  etat_du_dossier: en_instruction  # Trop tôt !
  champs: [...]

ma_config:
  demarches: [1234]
  when_ok:
    - publipostage: *template
```

✅ **Correct** : Définir `etat_du_dossier` au moment de l'utilisation
```yaml
template_publipostage: &template
  champs: [...]

action_publipostage: &action
  etat_du_dossier: en_instruction  # Ici c'est bon
  <<: *template

ma_config:
  demarches: [1234]
  when_ok:
    - publipostage: *action
```

### 3. Oublier `par défaut`

❌ **Incorrect** : Si la valeur ne correspond à aucun cas, erreur
```yaml
- conditional_field:
    champ: "Statut"
    valeurs:
      "Accepté":
        - action_1
      "Refusé":
        - action_2
      # Que se passe-t-il si Statut = "En attente" ?
```

✅ **Correct** :
```yaml
- conditional_field:
    champ: "Statut"
    valeurs:
      "Accepté":
        - action_1
      "Refusé":
        - action_2
      par défaut:  # Gère tous les autres cas
```

### 4. Variables dans les noms de champs

❌ **Incorrect** : Les accolades ne fonctionnent pas dans les noms de champs
```yaml
- conditional_field:
    champ: "{Nom du champ dynamique}"  # Ne fonctionne pas
```

✅ **Correct** : Les noms de champs sont littéraux
```yaml
- conditional_field:
    champ: "Nom exact du champ"
```

Mais les variables fonctionnent dans les **valeurs** :
```yaml
- set_field:
    champ: "Demandeur"
    valeur: "{demandeur.nom}"  # ✅ OK
```

### 5. Type des valeurs dans conditional_field

❌ **Incorrect** : Les valeurs booléennes YAML
```yaml
- conditional_field:
    champ: "Case à cocher"
    valeurs:
      true:        # Ne fonctionnera pas !
```

✅ **Correct** : Toujours utiliser des strings
```yaml
- conditional_field:
    champ: "Case à cocher"
    valeurs:
      "true":      # ✅ OK
```

### 6. Limitation actuelle : Comparaisons numériques

⚠️ **Non supporté actuellement** :
```yaml
- conditional_field:
    champ: "Montant"
    valeurs:
      "> 1000":    # Ne fonctionne pas
```

Il faut tester des valeurs exactes uniquement.

### 7. Charger les fichiers YAML en Ruby

❌ **Incorrect** :
```ruby
content = YAML.load_file(file_path)  # Erreur si anchors/aliases
```

✅ **Correct** :
```ruby
content = YAML.load_file(file_path, aliases: true)
```

### 8. Extension de fichier incorrecte

❌ **Incorrect** : Le fichier ne sera pas chargé
```
storage/configurations/ma_config.yaml
```

✅ **Correct** :
```
storage/configurations/ma_config.yml
```

Le système de chargement (`Tools::DiskFileManager`) recherche uniquement les fichiers avec l'extension `.yml`. Les fichiers `.yaml` seront ignorés et ne s'exécuteront jamais, même s'ils sont syntaxiquement corrects.

**Comment vérifier** :
```bash
# Lister tous les fichiers de configuration chargés
ls storage/configurations/*.yml

# Vérifier qu'un fichier spécifique sera chargé
test -f storage/configurations/ma_config.yml && echo "OK" || echo "Fichier ignoré"
```

## Ressources

- **Exemples en production** : `storage/configurations/` (privilégier les fichiers récents)
- **Code source** : `app/lib/` pour voir tous les FieldCheckers disponibles
- **Parsing** : `app/services/verification_service.rb` pour comprendre comment les configs sont chargées
- **Tests** : `spec/lib/` pour voir des exemples d'utilisation

## Validation d'une configuration

Avant de déployer une nouvelle configuration :

1. **Vérifier la syntaxe YAML** :
```bash
ruby -ryaml -e "YAML.load_file('storage/configurations/mon_fichier.yml', aliases: true)"
```

2. **Linter Ruby** :
```bash
bundle exec rubocop -A
```

3. **Lint global** :
```bash
bundle exec rake lint
```

4. **Tester sur un dossier de test** :
   - Créer un dossier de test dans Mes-Démarches
   - Lancer la vérification manuellement
   - Vérifier les logs et les résultats
