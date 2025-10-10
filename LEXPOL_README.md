# Automatisation du renommage de variables Lexpol

## 📋 Description

Script Python pour automatiser le renommage de variables dans le modèle Lexpol.
Lit un fichier CSV avec les mappings `old_variable → new_variable` et effectue les renommages automatiquement.

## 🚀 Installation

```bash
# Créer l'environnement virtuel (déjà fait)
python3 -m venv venv_lexpol

# Activer l'environnement
source venv_lexpol/bin/activate

# Installer les dépendances
pip install playwright
playwright install chromium
```

## 📁 Fichiers

- `lexpol_variable_renamer.py` : Script principal
- `lexpol_config.py` : Configuration (URLs, identifiants, timeouts)
- `lexpol_rename_mapping.csv` : Fichier CSV des renommages
- `logs/` : Dossier contenant les logs d'exécution

## 🎯 Utilisation

### 1. Préparer le fichier CSV

Éditer `lexpol_rename_mapping.csv` :

```csv
old_variable,new_variable
arrete.aCompterDe,arrete.aCompterDe_TEST
association.nom,association.nomComplet
```

### 2. Lancer le script

**Mode normal** (effectue les modifications) :
```bash
source venv_lexpol/bin/activate
python3 lexpol_variable_renamer.py
```

**Mode dry-run** (simule sans modifier) :
```bash
python3 lexpol_variable_renamer.py --dry-run
```

**Traiter une seule variable** :
```bash
python3 lexpol_variable_renamer.py --variable arrete.aCompterDe
```

**Utiliser un autre fichier CSV** :
```bash
python3 lexpol_variable_renamer.py --csv mon_fichier.csv
```

## 🔧 Configuration

Éditer `lexpol_config.py` pour modifier :
- URL du modèle Lexpol
- Identifiants de connexion
- Timeouts
- Mode headless (visible/invisible)

## 📊 Processus de renommage

Pour chaque variable du CSV, le script :

1. ✅ Se connecte au modèle Lexpol
2. ✅ Trouve la variable dans la liste
3. ✅ Recherche toutes les occurrences (popup)
4. ✅ Pour chaque occurrence :
   - Clique sur le lien
   - Trouve la zone d'édition
   - Remplace `{@old_variable@}` par `{@new_variable@}`
   - Valide selon le type (Contenu/Intitulé)
5. ✅ Renomme la définition de la variable
6. ✅ Affiche les statistiques

## 🎬 Exemple de sortie

```
[10:15:32] 🚀 Initialisation du navigateur...
[10:15:35] ✅ Navigateur initialisé
[10:15:36] 🔑 Connexion à Lexpol...
[10:15:40] ✅ Connecté au modèle Lexpol
[10:15:41] 📄 Lecture du fichier CSV: lexpol_rename_mapping.csv
[10:15:41] 📊 1 renommage(s) trouvé(s) dans le CSV

================================================================================
[10:15:41] 🎯 Traitement: arrete.aCompterDe → arrete.aCompterDe_TEST
================================================================================
[10:15:42] 🔍 Recherche de la variable: arrete.aCompterDe
[10:15:43] ✅ Variable trouvée: {@arrete.aCompterDe@} (ID: variable123456)
[10:15:43] 🔎 Recherche des occurrences de arrete.aCompterDe...
[10:15:45] 📊 2 occurrence(s) trouvée(s)
   1. Rapport de présentation - N5 - Contenu (type: CONTENU)
   2. Note de présentation - N0 - Contenu (type: CONTENU)

--- Occurrence 1/2 ---
[10:15:46] 📝 Traitement de l'occurrence: Rapport de présentation - N5 - Contenu
[10:15:47] ✅ Variable trouvée dans TEXTAREA
[10:15:48] ✅ Validation par clic (type CONTENU)
[10:15:49] ✅ Remplacement réussi dans Rapport de présentation - N5 - Contenu

[10:15:52] ✏️  Renommage de la définition: arrete.aCompterDe → arrete.aCompterDe_TEST
[10:15:53] ✅ Définition renommée
[10:15:53] 🎉 Renommage complet réussi: arrete.aCompterDe → arrete.aCompterDe_TEST

================================================================================
[10:15:54] 📊 STATISTIQUES FINALES
================================================================================
Total traité:    1
Succès:          1 ✅
Échecs:          0 ❌
Ignorés:         0 ⏭️
================================================================================
```

## ⚠️ Points d'attention

1. **Toujours tester en dry-run d'abord** : `--dry-run`
2. **Vérifier le CSV** : Format correct, pas de variables en double
3. **Connexion** : Vérifier les identifiants dans `lexpol_config.py`
4. **Navigation** : Le script navigue automatiquement, ne pas toucher au navigateur
5. **Erreurs** : En cas d'erreur, vérifier les logs pour diagnostiquer

## 🐛 Dépannage

**Le script ne trouve pas la variable** :
- Vérifier que la variable existe dans le modèle
- Vérifier l'orthographe exacte dans le CSV

**Le remplacement ne fonctionne pas** :
- Le script gère les types "Contenu" et "Intitulé"
- Pour d'autres types, une adaptation peut être nécessaire

**Timeout** :
- Augmenter les timeouts dans `lexpol_config.py`
- Ralentir les actions avec `SLOW_MO`

## 📝 Ajout de variables à renommer

Pour ajouter des variables au CSV, simplement éditer `lexpol_rename_mapping.csv` :

```csv
old_variable,new_variable
arrete.aCompterDe,arrete.aCompterDe_TEST
association.nom,association.nomComplet
demande.dateDemande,dossier.dateDepot
# Ajouter vos variables ici...
```

Le script traitera toutes les lignes séquentiellement.
