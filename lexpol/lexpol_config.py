#!/usr/bin/env python3
"""
Configuration pour l'automatisation Lexpol
"""
import os
from pathlib import Path
from dotenv import load_dotenv

# Charger les variables d'environnement depuis .env
# Chercher le .env dans le dossier lexpol (où se trouve ce fichier)
dotenv_path = Path(__file__).parent / '.env'
load_dotenv(dotenv_path=dotenv_path)

# URL du modèle Lexpol à modifier
LEXPOL_URL = "https://lexpol.cloud.pf/extranet/geda_dossier.php?idw=598470&hk=4088e2f4e3b32157927abd4c31858be9"

# Identifiants de connexion (depuis .env)
EMAIL = os.getenv('LEXPOL_USERNAME')
PASSWORD = os.getenv('LEXPOL_PASSWORD')

if not EMAIL or not PASSWORD:
    raise ValueError(
        "LEXPOL_USERNAME et LEXPOL_PASSWORD doivent être définis dans le fichier .env\n"
        "Copiez .env.example vers .env et remplissez vos identifiants."
    )

# Fichier CSV contenant les renommages (relatif au dossier lexpol)
CSV_FILE = str(Path(__file__).parent / "lexpol_rename_mapping.csv")

# Options d'exécution
HEADLESS = False  # False pour voir le navigateur, True pour mode invisible
SLOW_MO = 500     # Ralentissement en ms pour observer les actions (0 = vitesse normale)

# Timeouts (en millisecondes)
TIMEOUT_PAGE_LOAD = 30000      # 30 secondes pour charger une page
TIMEOUT_ELEMENT_WAIT = 10000   # 10 secondes pour attendre un élément
TIMEOUT_BETWEEN_STEPS = 2000   # 2 secondes entre chaque étape

# Logging
LOG_DIR = "logs"
LOG_LEVEL = "INFO"  # DEBUG, INFO, WARNING, ERROR
