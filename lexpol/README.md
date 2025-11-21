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

### Mode renommage

#### Renommer une seule variable (la première du CSV)
```bash
source venv/bin/activate
python3 lexpol_variable_renamer.py
```

#### Renommer toutes les variables du CSV
```bash
source venv/bin/activate
python3 lexpol_variable_renamer.py --all
```

### Mode nettoyage

#### Supprimer toutes les variables non utilisées
```bash
source venv/bin/activate
python3 lexpol_variable_renamer.py --cleanup
```

Cette option parcourt toutes les variables du modèle et supprime automatiquement celles qui n'ont aucune occurrence. Pour chaque variable :
- Recherche du nombre d'occurrences
- Si 0 occurrence : suppression automatique avec confirmation
- Affichage d'un résumé final (variables supprimées/conservées/ignorées)

**Note :** Cette option ne nécessite pas de fichier CSV et est indépendante du mode renommage.

### Mode extraction

#### Extraire la liste de toutes les variables
```bash
source venv/bin/activate
python3 lexpol_list_variables.py
```

Ce script génère un fichier CSV avec toutes les variables du modèle et leurs informations :
- Code de la variable
- Libellé (description)
- Nombre d'occurrences
- Statut (Utilisée / Non utilisée)

Le fichier généré porte le nom `lexpol_variables_YYYYMMDD_HHMMSS.csv` avec un timestamp pour éviter les écrasements.

### Mode tri

#### Trier les variables par ordre alphabétique
```bash
source venv/bin/activate
python3 lexpol_sort_variables.py
```

Ce script trie toutes les variables du modèle par ordre alphabétique :
- Respecte la casse (majuscules avant minuscules)
- **Ignore les accents** pour un tri naturel ("à" = "a", "é" = "e")
- Optimisé : déplace directement de N positions en un seul appel
- Recalcule l'ordre à chaque itération pour garantir la cohérence

#### Simulation du tri (dry-run)
```bash
source venv/bin/activate
python3 lexpol_sort_variables.py --dry-run
```

Affiche les déplacements qui seraient effectués sans les appliquer réellement.

### Paramètres optionnels (multi-comptes)

Tous les scripts de connexion acceptent des paramètres optionnels pour se connecter à différents modèles ou comptes :

#### Paramètre --modele
Permet de spécifier le numéro du modèle Lexpol à utiliser :
```bash
python3 lexpol_variable_renamer.py --modele 623774 --all
python3 lexpol_list_variables.py --modele 623774
python3 lexpol_sort_variables.py --modele 623774
```

#### Paramètre --email
Permet de spécifier l'email de connexion (complet ou juste le préfixe) :
```bash
# Avec préfixe (construit automatiquement redacteur.geda@jeunesse.gov.pf)
python3 lexpol_variable_renamer.py --email jeunesse --all

# Avec email complet
python3 lexpol_list_variables.py --email redacteur.geda@dgen.gov.pf

# Combinaison des deux
python3 lexpol_sort_variables.py --modele 623774 --email jeunesse
```

**Note :** Ces paramètres sont optionnels. Sans eux, les scripts utilisent les valeurs par défaut du fichier de configuration.

## Architecture

### Fichiers principaux

- **lexpol_variable_renamer.py** : Script principal orchestrant le renommage et le nettoyage
- **lexpol_list_variables.py** : Script d'extraction de toutes les variables (génère un CSV)
- **lexpol_sort_variables.py** : Script de tri alphabétique des variables (ignore les accents)
- **lexpol_strategies.py** : Gestionnaire de stratégies avec 8 stratégies de remplacement
- **lexpol_connection.py** : Gestion de la connexion et authentification à Lexpol (support multi-comptes)
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

## Corrections et améliorations récentes

### Gestion des caractères spéciaux
Le script gère correctement les noms de variables contenant des caractères spéciaux (accents, apostrophes, symboles comme °, etc.) grâce à l'utilisation de `page.evaluate()` avec passage de paramètres au lieu de f-strings JavaScript.

### Mode nettoyage automatique
Nouvelle fonctionnalité `--cleanup` qui permet de supprimer automatiquement toutes les variables non utilisées du modèle, avec gestion complète de la popup de confirmation.

## Notes importantes

- Le fichier `.env` est exclu de git (.gitignore)
- Le répertoire `venv/` est exclu de git
- Les identifiants ne doivent JAMAIS être commitées dans le code
- Le script utilise un mode non-headless pour observer les actions (configurable dans lexpol_config.py)
- Les noms de variables peuvent contenir des caractères spéciaux (accents, apostrophes, symboles)
