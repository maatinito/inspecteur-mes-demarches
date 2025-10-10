# Lexpol Variable Renamer

Outil automatisé de renommage de variables dans les modèles Lexpol utilisant Playwright.

## Installation

1. Créer et activer l'environnement virtuel :
```bash
cd lexpol
python3 -m venv venv
source venv/bin/activate
```

2. Installer les dépendances :
```bash
pip install playwright python-dotenv
playwright install chromium
```

3. Configurer les identifiants :
```bash
cp .env.example .env
# Éditer .env et renseigner vos identifiants Lexpol
```

## Configuration

### Fichier `.env`

Le fichier `.env` contient vos identifiants Lexpol (ne JAMAIS commiter ce fichier) :
```
LEXPOL_USERNAME=votre.email@example.com
LEXPOL_PASSWORD=votre_mot_de_passe
```

### Fichier `lexpol_rename_mapping.csv`

Ce fichier CSV définit les renommages à effectuer :
```csv
old_variable,new_variable
demande.compta.exercice,demande.compta.exercice1
demande.dateReception,demande.dateReception1
```

## Utilisation

### Renommer une seule variable (la première du CSV)
```bash
source venv/bin/activate
python3 lexpol_variable_renamer.py
```

### Renommer toutes les variables du CSV
```bash
source venv/bin/activate
python3 lexpol_variable_renamer.py --all
```

## Architecture

### Fichiers principaux

- **lexpol_variable_renamer.py** : Script principal orchestrant le renommage
- **lexpol_strategies.py** : Gestionnaire de stratégies avec 8 stratégies de remplacement
- **lexpol_connection.py** : Gestion de la connexion et authentification à Lexpol
- **lexpol_config.py** : Configuration (charge les variables d'environnement depuis .env)

### Les 8 stratégies de remplacement

1. **SquareEditStrategy** : Éléments avec icône square_edit.png (Référence)
2. **SimpleTextareaStrategy** : Textareas simples avec auto-save via blur
3. **SimpleSummernoteStrategy** : Éditeurs Summernote simples (icône f_edit.png)
4. **SummernoteStrategy** : Éditeurs Summernote avancés (Note de synthèse, Rapport)
5. **CCBFModalStrategy** : Popup CCBF avec bouton Valider
6. **ButtonSaveStrategy** : Éléments avec bouton "Enregistrer"
7. **IntituleStrategy** : Champ Intitulé avec gestion spéciale
8. **EditableTableStrategy** : Tableaux éditables (Parties signataires, Imputations budgétaires)

Chaque stratégie est documentée avec sa PHILOSOPHIE, IMPLÉMENTATION, et PARTICULARITÉS dans le code source.

## Flux de traitement

1. Connexion à Lexpol et déploiement de la section variables
2. Ouverture de tous les documents (optimisation pour Summernote)
3. Pour chaque variable du CSV :
   - Recherche de la variable dans la liste
   - Récupération des occurrences via popup de recherche
   - Filtrage des occurrences traitables par les stratégies
   - Traitement de chaque occurrence avec la stratégie appropriée
   - Vérification finale du nombre d'occurrences restantes
   - Si toutes traitées : renommage de la variable elle-même

## Fichiers de données

- `lexpol_defined_variables.txt` : Liste des variables définies dans le modèle
- `lexpol_used_variables_unique.txt` : Variables utilisées (unique)
- `lexpol_unused_variables.csv` : Variables non utilisées
- `lexpol_section_variables.csv` : Variables par section
- `lexpol_section_variables_enhanced.csv` : Variables avec métadonnées enrichies

## Notes importantes

- Le fichier `.env` est exclu de git (.gitignore)
- Le répertoire `venv/` est exclu de git
- Les identifiants ne doivent JAMAIS être commitées dans le code
- Le script utilise un mode non-headless pour observer les actions (configurable dans lexpol_config.py)
