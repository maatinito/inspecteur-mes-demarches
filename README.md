[![Continuous Integration](https://github.com/maatinito/inspecteur-mes-demarches/actions/workflows/ci.yml/badge.svg)](https://github.com/maatinito/inspecteur-mes-demarches/actions/workflows/ci.yml)

# Inspecteur Mes-Démarches

**Inspecteur Mes-Démarches** est un système automatisé de validation et de traitement des dossiers pour la plateforme gouvernementale **mes-démarches.gov.pf** de la Polynésie française. L'application effectue des contrôles automatiques, des calculs et des tâches de workflow sur les dossiers soumis par les utilisateurs.

## Fonctionnalités principales

- **Validation automatique** des dossiers et de leurs pièces jointes
- **Calculs automatisés** (montants, taxes, subventions)
- **Gestion des workflows** (acceptation, refus, instruction)
- **Intégration de paiement** via PayZen
- **Génération de documents** Excel et publipostage
- **Intégration Baserow** pour la gestion de données
- **Traitement spécialisé** par ministère/direction

## Technologies

- **Ruby** 3.3.1
- **Rails** 7.0.4
- **PostgreSQL** 16.9
- **Docker** pour le déploiement

## Développement

### Prérequis

- Ruby 3.3.1
- PostgreSQL 16.9
- Bundle

### Installation

```bash
# Cloner le projet
git clone <repository-url>
cd inspecteur-mes-demarches

# Installer les dépendances
bundle install

# Configurer la base de données
rails db:create db:migrate db:seed

# Lancer l'application
rails server
# ou avec webpack dev server
bin/dev
```

### Tests

```bash
# Tous les tests
bundle exec rspec

# Test spécifique
bundle exec rspec spec/path/to/file_spec.rb

# Test à une ligne précise
bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER
```

### Linting

```bash
# Tous les linters
bundle exec rake lint

# Rubocop uniquement
bundle exec rubocop --parallel

# SCSS linter
bundle exec scss-lint app/assets/stylesheets/
```

### Jobs

```bash
# Programmer les tâches cron
rails jobs:schedule

# Afficher le planning
rails jobs:display_schedule

# Lancer le worker
rails jobs:work
```

## Tâches disponibles

Les tâches suivantes sont organisées par catégorie et héritent de la classe `InspectorTask` :

### Gestion des dossiers

| Tâche | Description |
|-------|-------------|
| `DossierAccepter` | Accepte automatiquement un dossier |
| `DossierRefuser` | Refuse un dossier avec motivation |
| `DossierClasserSansSuite` | Classe un dossier sans suite |
| `DossierPasserEnInstruction` | Passe un dossier en instruction |
| `DossierRepasserEnInstruction` | Remet un dossier en instruction |

### Validation et contrôles

| Tâche | Description |
|-------|-------------|
| `MandatoryFieldCheck` | Vérifie la présence des champs obligatoires |
| `RegexCheck` | Valide les champs avec des expressions régulières |
| `ExcelCheck` | Contrôle la validité des fichiers Excel |
| `ConditionalField` | Validation conditionnelle de champs |

### DAF (Direction des Affaires Foncières)

| Tâche | Description |
|-------|-------------|
| `Daf::Instruction` | Gestion du processus de paiement pour l'enregistrement foncier |
| `Daf::Amount` | Calcul des montants des droits d'enregistrement |
| `Daf::BillValues` | Traitement et calcul des factures |
| `Daf::ActCopyAmount` | Calcul des montants pour copies d'actes |
| `Daf::CopyOrder` | Traitement des commandes de copies |
| `Daf::RejectInvalidFiles` | Rejet des fichiers invalides (limites de nombre) |
| `Daf::IfAdministration` | Exécution conditionnelle pour entités administratives |
| `Daf::Message` | Fonctionnalités de messagerie DAF |

### Santé

| Tâche | Description |
|-------|-------------|
| `Sante::Instruction` | Traitement des instructions secteur santé |
| `Sante::IbanValues` | Validation et traitement IBAN |
| `Sante::SubsidyValues` | Calcul des subventions santé |

### CIS (Formation)

| Tâche | Description |
|-------|-------------|
| `Cis::Consolidation` | Consolidation des données de formation |
| `Cis::GenererModeleEtatReel` | Génération de modèles d'état réel |
| `Cis::CalculeActivite` | Calculs d'activité |
| `Cis::PosterEtatsReels` | Publication des états réels |

### DESETI (Services sociaux)

| Tâche | Description |
|-------|-------------|
| `Deseti::Instruction` | Automatisation instruction DESETI/mini-DESETI |
| `Deseti::MessageDeseti` | Messagerie DESETI |

### DJS (Jeunesse et Sports)

| Tâche | Description |
|-------|-------------|
| `Djs::IfCompanyAge` | Validation âge entreprise pour programmes jeunesse/sport |

### PayZen (Paiements)

| Tâche | Description |
|-------|-------------|
| `Payzen::PaymentOrder` | Création et gestion des ordres de paiement |
| `Payzen::Task` | Fonctionnalités de base PayZen |
| `Payzen::Taxes` | Calculs de taxes pour paiements |

### Calculs

| Tâche | Description |
|-------|-------------|
| `Calculs::AmountInLetters` | Conversion montants en lettres |
| `Calculs::EmailToNames` | Extraction noms depuis emails |
| `Calculs::FloatToPercent` | Conversion décimaux en pourcentages |
| `Calculs::RepetitionCount` | Comptage répétitions dans formulaires |
| `Calculs::Sums` | Calculs de sommes sur champs |

### Excel

| Tâche | Description |
|-------|-------------|
| `Excel::FromRepetitions` | Génération Excel depuis données répétitives |
| `Excel::Group` | Groupement de données pour Excel |
| `Excel::Partition` | Partitionnement de données Excel |
| `Excel::GetSheets` | Extraction informations feuilles Excel |

### Actions et utilitaires

| Tâche | Description |
|-------|-------------|
| `SendMail` | Envoi d'emails automatiques |
| `SetAnnotation` | Définition d'annotations |
| `SetField` | Modification de champs |
| `Publipostage` | Publipostage/mail merge |
| `NumeroDn` | Traitement numéros DN |
| `DateDeNaissance` | Traitement dates de naissance |
| `CopyFileField` | Copie de champs fichiers |

### Intégration

| Tâche | Description |
|-------|-------------|
| `Baserow::Examples::BaserowIntegrationTask` | Intégration base de données Baserow |

## Configuration

### Variables d'environnement

Créer un fichier `.env` avec les variables suivantes :

```env
ROOT=chemin vers le répertoire contenant le .env
IMAGE=matau/imd
TAG=latest

DB_DATABASE=Nom de la base à créer
DB_HOST=db
DB_USERNAME=postgres
DB_PASSWORD=mot_de_passe

PORT=3000

# Paramètres GraphQL
GRAPHQL_HOST=https://www.mes-demarches.gov.pf
GRAPHQL_BEARER=Token Mes-Démarches permettant l'accès aux démarches

# Accès CPS pour les numéros DN
API_CPS_USERNAME=
API_CPS_PASSWORD=
API_CPS_CLIENT_ID=
API_CPS_CLIENT_SECRET=

# Baserow (optionnel)
BASEROW_URL=https://baserow.mes-demarches.gov.pf
BASEROW_API_TOKEN=your_token
BASEROW_TOKEN_TABLE=table_id
```

### Fichiers de configuration YAML

Les fichiers de configuration YAML définissent les contrôles automatiques à effectuer sur les dossiers. Ils doivent être placés dans `storage/configurations/`.

**Documentation :**
- [Guide complet de configuration YAML](docs/CONFIGURATION_GUIDE.md) - Syntaxe, FieldCheckers disponibles, exemples
- [CLAUDE.md](CLAUDE.md) - Instructions pour Claude Code, incluant le processus de déploiement

**Déploiement :**
Les fichiers de configuration ne sont pas versionnés dans Git. Pour déployer :
1. Développer dans `storage/configurations/`
2. Copier vers `robot-mes-demarches-staging` (dev) ou `robot-mes-demarches-production` (master)
3. Exécuter `mirror_staging.sh` ou `mirror_production.sh`

Voir [CLAUDE.md](CLAUDE.md#configuration-deployment-process) pour les détails.

## Architecture

L'application est organisée autour de deux concepts principaux :

1. **FieldChecker** : Classes de validation et traitement des champs de formulaire
2. **InspectorTask** : Tâches automatisées sur les dossiers

Les tâches sont organisées par ministère/direction (DAF, Santé, CIS, DESETI, DJS) et par type de fonctionnalité (validation, calculs, paiements, etc.).

## Contribution

1. Créer une branche feature
2. Implémenter les modifications avec tests
3. Vérifier le linting : `bundle exec rake lint`
4. Soumettre une pull request

## Licence

Ce projet est développé pour l'administration de la Polynésie française.