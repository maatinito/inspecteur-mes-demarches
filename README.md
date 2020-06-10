# Inspecteur Mes-Démarches

L'inspecteur mes-démarches est un prototype de controle des dossiers dans https://www.mes-démarches.gov.pf.

## ruby
Pour des raisons de rapidité de mise en oeuvre, le porotype utilise les même technologies que mes-démarches: 
* Ruby 2.6.5
* Rails 5.2
* PostgreSQL 10

# Variables d'environnement
Pour fonctionner, l'application requiert un fichier .env contenant la définition des variables suivantes: 
```.env
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
# Configuration
La configuration de l'application necessite un fichier auto-instructeur.yml donnant la liste des contrôles à effectuer sur Mes-Démarches.


# Déploiement 
Le projet peut se déployer à l'aide de docker compose et instancie l'application et postgres. 
Une image de l'application est déployées sur DockerHub. Etapes minimales: 
* curl -OL https://raw.githubusercontent.com/maatinito/inspecteur-mes-demarches/$BRANCH/docker-compose.yml
* mkdir downloads postgres storage uploads
* mettre le fichier auto-instructeur.yml dans le dossier storage
* docker-compose pull
* docker-compose up -d 

La base de données sera créé automatiquement au premier lancement et sauvegardé dans le sous répertoire postgres.
