# Gestion des erreurs réseau - Éviter les emails multiples

## Problème résolu

Lorsque l'API mes-démarches.gov.pf n'est pas disponible, la classe `VerificationService` générait de multiples emails d'erreur :
- Un email par démarche traitée dans le même cycle
- Un email à chaque exécution du job cron (toutes les 6 minutes)

## Solution implémentée

### 1. Vérification de disponibilité

La méthode `VerificationService#check` vérifie déjà la disponibilité de l'API avec `DemarcheActions.ping` avant de commencer le traitement.

### 2. Système de throttling des emails

Un système de cooldown d'1 heure a été implémenté pour éviter l'envoi répétitif d'emails pour les mêmes erreurs réseau :

- **Détection des erreurs réseau** : Identification automatique des erreurs liées à la connectivité
- **Throttling par type d'erreur** : Limitation d'un email par heure par type d'erreur réseau
- **Préservation des autres erreurs** : Les erreurs non-réseau continuent d'être notifiées normalement

### 3. Nouvelles méthodes ajoutées

```ruby
# Vérifie si une erreur doit déclencher une notification
def should_notify_error?(message, exception)

# Marque une erreur comme ayant été notifiée
def mark_error_notified(message, exception)

# Détecte si une exception est liée au réseau
def network_error?(exception)

# Génère une clé unique pour identifier le type d'erreur
def network_error_key(message, exception)

# Nettoie le cache des notifications (pour les tests)
def self.clear_network_error_notifications
```

### 4. Patterns d'erreurs réseau détectés

Les erreurs contenant ces termes sont considérées comme des erreurs réseau :
- `connection` (Connection refused, Connection timeout, etc.)
- `timeout` (Network timeout, Request timeout, etc.)
- `network` (Network unreachable, etc.)
- `host` (Host not found, etc.)
- `resolve` (DNS resolution failed, etc.)
- `refused` (Connection refused, etc.)
- `unreachable` (Network unreachable, etc.)
- `socket` (Socket error, etc.)

## Utilisation

Aucune modification nécessaire dans le code existant. Le système fonctionne automatiquement :

```ruby
# Avant : chaque erreur réseau envoyait un email
service.report_error("Network error", StandardError.new("Connection refused"))
service.report_error("Network error", StandardError.new("Connection refused")) # -> email envoyé
service.report_error("Network error", StandardError.new("Connection refused")) # -> email envoyé

# Après : throttling automatique
service.report_error("Network error", StandardError.new("Connection refused")) # -> email envoyé
service.report_error("Network error", StandardError.new("Connection refused")) # -> pas d'email (cooldown)
service.report_error("Network error", StandardError.new("Connection refused")) # -> pas d'email (cooldown)
```

## Tests

Les tests couvrent :
- Détection des erreurs réseau vs non-réseau
- Mécanisme de throttling
- Respect de la période de cooldown
- Fonctionnement normal pour les erreurs non-réseau

```bash
bundle exec rspec spec/lib/verification_service_spec.rb
```