# describe_demarche

Script pour afficher la structure complète d'une démarche Mes-Démarches.

## Usage

```bash
./bin/describe_demarche <numero_demarche>
```

## Exemple

```bash
./bin/describe_demarche 3508
```

## Sortie

Le script affiche :

1. **Titre de la démarche** avec son numéro
2. **CHAMPS** (remplis par l'usager)
   - Affichage hiérarchique avec indentation
   - Sections et sous-sections
   - Pour chaque champ : `Libellé : Type { options }`
3. **ANNOTATIONS PRIVÉES** (remplies par les agents)
   - Même format que les champs

## Format d'affichage

```
Section principale
  Sous-section
    Champ : Type { required=true, options=[...] }
    Bloc répétable : Repetition { required=true }
      Sous-champ : Text { required=false }
```

## Types de champs courants

- `Text` : Champ texte
- `DropDownList` : Liste déroulante
- `Repetition` : Bloc répétable
- `PieceJustificative` : Fichier à télécharger
- `Email`, `Date`, `YesNo`, `Civilite`, etc.

## Options affichées

- `required` : Champ obligatoire (true/false)
- `options` : Valeurs possibles pour les listes déroulantes

## Gestion d'erreurs

- Démarche inexistante : affiche "Demarche not found"
- Numéro invalide : affiche l'usage du script
- Erreur réseau : affiche le message d'erreur
