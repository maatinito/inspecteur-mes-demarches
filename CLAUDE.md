# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Inspecteur Mes-Démarches is a Ruby on Rails application that validates and processes files uploaded to the "mes-démarches.gov.pf" platform, which is a government platform for French Polynesia. The application performs various checks and automated tasks on dossiers (application files) submitted through the platform.

## RÈGLES CRITIQUES - À RESPECTER ABSOLUMENT

### Commit Guidelines
- Dans ce projet, les commits ne doivent ABSOLUMENT PAS mentionner Claude
- Avant chaque commit, il est OBLIGATOIRE de :
  * Exécuter un rubocop -A (pour corriger automatiquement)
  * Exécuter un lint

## Development Commands

### Setup

```bash
# Install dependencies
bundle install

# Setup database
rails db:create db:migrate db:seed

# Run the development server
rails server

# Run the development server with webpack dev server
bin/dev
# or
foreman start -f Procfile.dev
```

### Testing

```bash
# Run all tests
bundle exec rspec

# Run a specific test file
bundle exec rspec spec/path/to/file_spec.rb

# Run a specific test by line number
bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER
```

### Linting

```bash
# Run all linters
bundle exec rake lint

# Run Rubocop only
bundle exec rubocop --parallel

# Run SCSS linter
bundle exec scss-lint app/assets/stylesheets/
```

### Jobs

```bash
# Schedule all cron jobs
rails jobs:schedule

# Display schedule for all cron jobs
rails jobs:display_schedule

# Run delayed jobs worker
rails jobs:work
```

## Project Structure

The application is organized around:

1. **FieldChecker subclasses**: Implements validation and business logic for specific form fields or documents
2. **InspectorTask subclasses**: Performs automated tasks on dossiers
3. **Jobs**: Scheduled and background tasks that run inspections and checks
4. **Models**: Active Record models that interact with the database

Key components:

- `app/lib/`: Contains most of the business logic for validating and processing dossiers
- `app/jobs/`: Contains background jobs including cron jobs
- `app/models/`: Database models
- `spec/`: Tests for the application

## Docker Setup

The application can be run using Docker:

```bash
# Pull the latest image
docker-compose pull

# Start the containers
docker-compose up -d
```

The Docker setup includes:
- A Rails application container
- A worker container for background jobs
- Shared volumes for storage and fonts

## Environment Variables

The application requires a `.env` file with the following variables:

```
ROOT=chemin vers le répertoire contenant le .env
IMAGE=matau/imd
TAG=latest

DB_DATABASE=Nom de la base à créer
DB_HOST=db
DB_USERNAME=postgres
DB_PASSWORD=_mot de passe_ 

PORT=3000

# GRAPHQL parameters
GRAPHQL_HOST=https://www.mes-demarches.gov.pf
GRAPHQL_BEARER=Token Mes-Démarches permettant l'accès aux démarches (profil administrateur)

# Access CPS pour les numéro DN si utilisation du controle res_excel 
API_CPS_USERNAME=
API_CPS_PASSWORD=
API_CPS_CLIENT_ID=
API_CPS_CLIENT_SECRET=
```

## Configuration

The application requires a configuration file named `auto-instructeur.yml` that lists the checks to perform on Mes-Démarches platform. This file should be placed in the `/storage` directory.

## Working with the Code

When implementing a new check or task:

1. Create a new class that inherits from `FieldChecker` or `InspectorTask`
2. Implement the `process` method to perform your logic
3. Write tests in the `spec/lib/` directory
4. Make sure to handle various edge cases and potential errors

## Baserow Integration

The application includes a client for interacting with Baserow, a no-code database platform similar to Airtable.

### Configuration

To use the Baserow integration, set the following environment variables:

```
BASEROW_URL=https://baserow.mes-demarches.gov.pf
BASEROW_API_TOKEN=your_default_token
BASEROW_TOKEN_TABLE=table_id_containing_tokens
```

The `BASEROW_TOKEN_TABLE` is optional and should point to a Baserow table containing tokens for different configurations. This table should have columns for the configuration name and the token.

Named configuration tokens are cached for 1 hour to minimize API calls. The default token is not cached since it comes from an environment variable. You can clear the cache programmatically with `Baserow::TokenManager.clear_cache`.

### Basic Usage

```ruby
# Get a client instance with default token
client = Baserow::Config.client

# Get a client instance with a specific configuration token
tftn_client = Baserow::Config.client('tftn')

# Get a specific table
table_info = client.get_table('table_id')

# Work with a specific table (default token)
contacts_table = Baserow::Config.table('table_id', nil, 'Contacts')

# Work with a specific table using a named configuration
planning_table = Baserow::Config.table('table_id', 'tftn', 'Planning')

# List all records
all_contacts = contacts_table.all

# Search for records
results = contacts_table.search('Name', 'John')

# Create a record
new_record = contacts_table.create_row({
  'Name' => 'John Doe',
  'Email' => 'john.doe@example.com'
})

# Update a record
contacts_table.update_row(record_id, {
  'Email' => 'new.email@example.com'
})

# Delete a record
contacts_table.delete_row(record_id)
```

See `app/lib/baserow/examples.rb` for more examples of how to use the Baserow integration.

## YAML Configuration Files Analysis

When analyzing YAML configuration files in this project, follow these important rules:

### Loading YAML Files with Aliases
Always use the `aliases: true` parameter when loading YAML files to properly resolve YAML references (`&name` and `*name`):

```ruby
# Correct way to load YAML files in this project
content = YAML.load_file(file_path, aliases: true)
```

Without this parameter, you will get "Unknown alias" errors when the YAML contains references.

### Configuration Entry Points
The configuration system uses a specific structure where only certain blocks are actual entry points:

- **Entry points**: Blocks that contain a `demarches` attribute are the real configuration entry points that will be executed by VerificationService
- **Templates/References**: All other blocks (like `publipostage: &template_name`) are reusable templates that are never executed directly

### Example Structure
```yaml
# This is a TEMPLATE - not executed directly
template_publipostage: &template_publipostage
  champs: [...]
  calculs: [...]
  # No need for etat_du_dossier here

poster_facture: &poster_facture
  etat_du_dossier: en_instruction  # Required here
  message: "..."
  <<: *template_publipostage       # Inherits from template

# This is an ENTRY POINT - will be executed
my_configuration:
  demarches: [1234, 5678]           # This identifies an entry point
  email_instructeur: test@example.com
  when_ok:
    - publipostage: *poster_facture # Real usage with etat_du_dossier
```

### Analysis Rules
When analyzing publipostage/publipostage_v2 tasks:
1. Only analyze tasks within blocks that have `demarches` attribute
2. Ignore template definitions (blocks without `demarches`)
3. Check that each actual task usage has `etat_du_dossier` either directly or inherited via `<<:`

This approach avoids false positives when checking for missing `etat_du_dossier` attributes.

## Project Guidelines

## Terminologie et Clarifications

### Distinction entre 'champ' et 'annotation'
- Le terme 'champ' du dossier est ambigu car il désigne parfois des annotations privées
- Les champs correspondent aux valeurs entrées par l'usager
- Les annotations privées correspondent aux informations données par les agents
- Par abus de langage, on utilise souvent 'champ' pour les deux, ce qui peut fausser les spécifications
- Il faut toujours savoir où se situe la donnée pour utiliser soit `param_field`, soit `param_annotation`
- Seules les annotations privées peuvent être modifiées à travers la classe `SetAnnotationValue`