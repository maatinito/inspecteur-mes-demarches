# QR Codes dans PublipostageV3

## Vue d'ensemble

Le système de QR codes permet de générer des codes QR dans les documents Word via PublipostageV3.
L'implémentation suit le même pattern que `PieceJustificativeFile` pour une API cohérente.

## Architecture

### QrcodeCache
- Cache basé sur le contenu (checksum SHA256)
- Utilise `PieceJustificativeCache.get_or_generate()` en interne
- Stockage dans `storage/pjs/` (partagé avec les pièces justificatives)
- Nettoyage automatique LRU (50MB max, géré par PieceJustificativeCache)
- Réutilisation des QR codes identiques

### QrcodeField
- Wrapper compatible Sablon
- Lazy loading de l'image
- Méthodes : `image`, `url`, `lien`, `present?`
- API cohérente avec `PieceJustificativeFile`

### Qrcode (FieldChecker)
- Hérite de `FieldChecker` pour accéder à `instanciate()`
- Génère les QrcodeField à partir d'un template
- Utilise `instanciate()` héritée (supporte préfixes, ternaires, accès aux champs)
- S'intègre dans le système de calculs de Publipostage

## Configuration YAML

```yaml
calculs:
  - qrcode:
      colonne: "qrcode"              # Nom de la colonne dans le template
      contenu: "https://..."         # Template du contenu à encoder
      taille: 300                    # Optionnel, 300px par défaut
```

### Syntaxe du template `contenu`

La méthode `instanciate()` supporte :

**Variables simples :**
```yaml
contenu: "https://mes-demarches.gov.pf/dossiers/{numero}"
# → https://mes-demarches.gov.pf/dossiers/12345
```

**Préfixes/suffixes conditionnels :**
```yaml
contenu: "{Dossier n°;numero}"
# Si numero existe : "Dossier n°12345"
# Si numero vide : ""
```

**Expressions ternaires :**
```yaml
contenu: "{numero?https://url.com/{numero}:Pas de numéro}"
# Si numero existe : "https://url.com/12345"
# Si numero vide : "Pas de numéro"
```

## Utilisation dans les templates Sablon

### Image seule
```
«@qrcode.image:start»[placeholder image]«@qrcode.image:end»
```

### Image + URL
```
«@qrcode.image:start»[img]«@qrcode.image:end»

Scannez ce code ou utilisez ce lien :
«=qrcode.url»
```

### Conditionnel
```
«qrcode:if(present?)»
  «@qrcode.image:start»[img]«@qrcode.image:end»
  Lien : «=qrcode.url»
«qrcode:endIf»
```

## Exemples complets

### QR code vers dossier mes-démarches
```yaml
calculs:
  - qrcode:
      colonne: "qrcode_dossier"
      contenu: "https://www.mes-demarches.gov.pf/dossiers/{numero}"
      taille: 300
```

### QR code email
```yaml
calculs:
  - qrcode:
      colonne: "qrcode_contact"
      contenu: "mailto:{email}?subject=Dossier {numero}&body=Bonjour {nom}"
      taille: 250
```

### QR code téléphone
```yaml
calculs:
  - qrcode:
      colonne: "qrcode_tel"
      contenu: "tel:{telephone}"
      taille: 200
```

### QR code vCard
```yaml
calculs:
  - qrcode:
      colonne: "qrcode_vcard"
      contenu: "BEGIN:VCARD\nVERSION:3.0\nFN:{nom} {prenom}\nTEL:{telephone}\nEMAIL:{email}\nEND:VCARD"
      taille: 300
```

## Fonctionnement avec `same_document`

Le système compare uniquement les **données** du QR code, pas l'image générée :

```ruby
# Génération 1
{ "_qrcode" => true, "data" => "https://example.com/123", "size" => 300 }

# Génération 2 (mêmes données)
{ "_qrcode" => true, "data" => "https://example.com/123", "size" => 300 }
# ✅ same_document détecte qu'il n'y a pas de changement

# Génération 3 (données différentes)
{ "_qrcode" => true, "data" => "https://example.com/456", "size" => 300 }
# ✅ same_document détecte le changement et régénère
```

Grâce au cache `QrcodeCache`, l'image n'est générée qu'une seule fois pour un même contenu.

## Maintenance

### Nettoyage manuel du cache
```ruby
# Nettoie tous les fichiers en cache (QR codes ET pièces justificatives)
PieceJustificativeCache.clean
```

### Vérification de la taille du cache
```bash
# Les QR codes sont dans le même répertoire que les pièces justificatives
du -sh storage/pjs/
```

Le nettoyage automatique maintient le cache sous 50MB en supprimant les fichiers les plus anciens (LRU).
Les QR codes partagent le même cache que les `PieceJustificativeFile`, ce qui simplifie la gestion.
