# Migration vers le nouveau dashboard de schéma (Slice 1)

La refonte UI introduit un dashboard par démarche avec persistance des cibles
Baserow/Grist via la table `schema_targets`.

Si la base contient déjà des démarches synchronisées via l'ancienne interface
(`MesDemarchesToBaserow::SchemaBuilder` / `MesDemarchesToGrist::SchemaBuilder`),
exécuter la tâche de backfill pour pré-remplir les `SchemaTarget` :

```bash
bundle exec rake schema_targets:backfill
```

## Ce que fait la tâche

- Parcourt toutes les `Demarche` de la base.
- Pour chacune, interroge Baserow puis Grist (via les adapters
  `SchemaBuilders::BaserowTarget` / `SchemaBuilders::GristTarget`) afin de
  détecter une table de schéma déjà créée.
- Heuristique de détection : table nommée `Dossiers démarche <id>` (convention
  du nouveau dashboard, cf.
  `Admin::SchemaBuilderController#main_table_name_for`).
- Si la table principale est trouvée, recherche en plus la table `Avis`
  associée et capture son identifiant.
- Crée un `SchemaTarget` avec `workspace_external_id`,
  `application_external_id`, `main_table_external_id` et éventuellement
  `avis_table_external_id`.

## Garanties

- **Idempotente** : rejouer la tâche ne crée pas de doublons (un `SchemaTarget`
  existant pour une `(démarche, target_type)` est sauté).
- **Résiliente** : une erreur API (Baserow down, Grist non configuré, etc.)
  sur une démarche n'arrête pas le batch — l'erreur est loggée puis la tâche
  passe à la cible / démarche suivante.

## Limites

- L'heuristique repose sur la convention de nommage actuelle
  (`Dossiers démarche <id>`). Les anciennes tables créées manuellement avec un
  nom différent ne seront pas détectées.
- Les démarches non détectées seront reconfigurées manuellement par
  l'utilisateur au prochain accès à `/admin/demarches/:id/schema`.

## Quand l'exécuter

À exécuter **une fois** après la mise en production de la Slice 1 du dashboard
de schéma, sur l'environnement contenant déjà des synchronisations historiques.
La tâche est sûre à rejouer ponctuellement après ajout/migration de démarches.
