# Lexpol Variable Renaming Tool

## But du programme

Outil d'automatisation pour renommer des variables dans l'éditeur Lexpol. Le programme utilise Playwright pour automatiser la navigation web et effectuer des remplacements de variables à travers différents types d'interfaces (textareas, éditeurs Summernote, modales, tableaux, etc.).

### Fonctionnalités principales

- Renommage automatique de variables Lexpol au format `{@variable@}`
- Support des suffixes (ex: `{@variable@:minuscules}`)
- Support du format `_en_lettres` (ex: `{@variable_en_lettres@}`)
- Gestion de multiples types d'interfaces via pattern Strategy
- Mode dry-run pour tester sans modifier
- Mode variable unique pour traiter une seule variable

## Fichiers créés

### Fichiers principaux

- **`lexpol_variable_renamer.py`** - Script principal avec CLI
- **`lexpol_strategies.py`** - Architecture Strategy pour gérer différents types d'occurrences
- **`lexpol_connection.py`** - Gestion de la connexion et authentification à Lexpol
- **`lexpol_config.py`** - Configuration (URL, credentials, fichiers)
- **`lexpol_rename_mapping.csv`** - Fichier CSV avec les mappings old_variable → new_variable

### Fichiers de test

- **`lexpol_simple_test.py`** - Test simplifié pour une seule variable
- **`fix_all_strategies.py`** - Script temporaire pour appliquer des modifications globales

## Stratégies implémentées

Le programme utilise différentes stratégies pour gérer les types d'occurrences :

1. **SquareEditStrategy** - Champs en édition directe (icône crayon)
2. **SummernoteStrategy** - Éditeurs WYSIWYG Summernote
3. **CCBFModalStrategy** - Modales de conditions/calculs
4. **SimpleTextareaStrategy** - Textareas simples
5. **SignataireTableStrategy** - Tableaux de signataires avec cellules cliquables

## Format du CSV

Le fichier `lexpol_rename_mapping.csv` doit contenir deux colonnes :

```csv
old_variable,new_variable
association.civilitePresident,Civilité du président
demande.numero,Numéro de demande
```

## Lancement du programme

### Prérequis

1. Installer l'environnement virtuel :
```bash
python3 -m venv venv_lexpol
source venv_lexpol/bin/activate
pip install playwright
playwright install chromium
```

2. Configurer `lexpol_config.py` avec :
   - URL de Lexpol
   - Identifiants de connexion
   - Chemin du fichier CSV

### Quel fichier Python lancer ?

**IMPORTANT pour le développeur futur** :

#### ✅ Fichier actuel FONCTIONNEL : `lexpol_simple_test.py`
```bash
source venv_lexpol/bin/activate
python3 lexpol_simple_test.py
```

**C'est LE SEUL fichier à utiliser et maintenir.**

Ce fichier :
- Utilise l'architecture moderne avec `StrategyManager` (voir `lexpol_strategies.py`)
- Utilise `LexpolConnection` pour la connexion
- Traite la première variable du CSV de mapping
- 250 lignes de code clair et maintenable
- Toutes les stratégies ont été développées et testées dans ce fichier

#### ❌ Fichier OBSOLÈTE : `lexpol_variable_renamer.py`

**⚠️ NE PAS UTILISER - Code complètement dépassé**

Ce fichier (983 lignes) :
- N'utilise PAS le `StrategyManager` moderne
- N'utilise PAS `LexpolConnection`
- Contient un ancien système de stratégies internes (try_edit_with_icon, try_summernote_edit, etc.)
- N'a PAS été maintenu depuis 24h de développement
- Doit être **supprimé** ou **complètement réécrit**

### Évolution future recommandée

**Option 1 : Renommer et étendre simple_test (RECOMMANDÉ)**
1. Renommer `lexpol_simple_test.py` → `lexpol_variable_renamer.py`
2. Ajouter des options CLI :
```python
parser = argparse.ArgumentParser(description='Renommer des variables dans Lexpol')
parser.add_argument('--all', action='store_true', help='Traiter toutes les variables du CSV')
parser.add_argument('--variable', help='Traiter uniquement cette variable spécifique')
parser.add_argument('--dry-run', action='store_true', help='Mode simulation sans modification')

# Par défaut (sans options) : traite la première variable (comportement actuel)
# --all : traite toutes les variables du CSV
# --variable X : traite uniquement la variable X
```

**Option 2 : Garder simple_test et supprimer l'ancien**
1. Supprimer `lexpol_variable_renamer.py` (obsolète)
2. Garder `lexpol_simple_test.py` comme seul outil
3. Ajouter des fonctionnalités au fur et à mesure des besoins

### Fichier à lancer ACTUELLEMENT

```bash
# Activer l'environnement virtuel
source venv_lexpol/bin/activate

# Lancer le renommage de la première variable du CSV
python3 lexpol_simple_test.py
```

Le script va :
1. Lire la première ligne de `lexpol_rename_mapping.csv`
2. Se connecter à Lexpol
3. Rechercher toutes les occurrences de la variable
4. Utiliser le `StrategyManager` pour traiter chaque occurrence avec la stratégie appropriée
5. Vérifier que tous les remplacements ont réussi
6. Si succès complet : renommer la définition de la variable elle-même

## Workflow du programme

1. **Connexion** - Authentification à Lexpol via `LexpolConnection`
2. **Lecture CSV** - Chargement des mappings de renommage
3. **Pour chaque variable** :
   - Recherche de la variable dans la liste
   - Clic sur l'icône de recherche pour lister les occurrences
   - Pour chaque occurrence :
     - Détermination de la stratégie appropriée via `StrategyManager`
     - Traitement selon la stratégie sélectionnée
     - Remplacement avec support des suffixes
   - Vérification finale du nombre de remplacements

## Architecture Strategy Pattern

```
StrategyManager
├── SquareEditStrategy
├── SummernoteStrategy
├── CCBFModalStrategy
├── SimpleTextareaStrategy
└── SignataireTableStrategy
```

Chaque stratégie implémente :
- `can_handle(occurrence_text)` : Détermine si elle peut traiter l'occurrence
- `process(page, occurrence, old_pattern, new_pattern)` : Effectue le remplacement

## Gestion des suffixes

Le programme préserve les suffixes lors du remplacement :

- `{@old_var@}` → `{@new_var@}`
- `{@old_var@:minuscules}` → `{@new_var@:minuscules}`
- `{@old_var_en_lettres@}` → `{@new_var_en_lettres@}`
- `{@old_var_en_lettres@:majuscules}` → `{@new_var_en_lettres@:majuscules}`

## Notes techniques

- **Headless mode** : Désactivé par défaut pour observer le comportement (`headless=False`)
- **Slow motion** : 500ms par défaut pour faciliter le débogage
- **Timeouts** : Délais configurés pour stabilisation du DOM après modifications
- **Regex patterns** : Utilisation de regex JavaScript pour capturer et préserver les suffixes
