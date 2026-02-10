# Solution 2 : Normalisation des civilités - IMPLÉMENTÉE ✅

**Date**: 2026-02-10
**Problème**: 45 documents en production seraient régénérés uniquement à cause du changement M./Mme → Monsieur/Madame
**Solution**: Skip la régénération si seule la civilité a changé

---

## 🎯 Objectif

Permettre le déploiement du changement civilités **sans régénérer** les 45 documents en cours en production.

---

## ✅ Ce qui a été implémenté

### 1. Normalisation des données dans `app/lib/publipostage.rb`

**Méthode `normalize_civilites_in_data`**
- Parcourt récursivement les données (Hash, Array, String)
- Transforme toutes les civilités en forme longue pour comparaison homogène
- Préserve les autres valeurs inchangées

**Méthode `normalize_civilite_value`**
- `M.` ou `M` → `Monsieur`
- `Mme` ou `Mlle` → `Madame`
- Autres valeurs → inchangées

### 2. Comparaison normalisée avant génération

**Modifications dans la méthode `already_generated?`** (ligne ~370-383) :

```ruby
# AVANT
same = data.present? && JSON.parse(data.data.to_json) == JSON.parse(stable_fields.to_json)

# APRÈS
normalized_old = data.present? ? normalize_civilites_in_data(data.data) : nil
normalized_new = normalize_civilites_in_data(stable_fields)

same = normalized_old.present? &&
       JSON.parse(normalized_old.to_json) == JSON.parse(normalized_new.to_json)
```

**Comportement** :
- Les anciennes données avec "M." sont normalisées en "Monsieur"
- Les nouvelles données avec "Monsieur" restent "Monsieur"
- Comparaison : "Monsieur" == "Monsieur" → **IDENTIQUE**
- **Document non régénéré** ✅

---

## 🧪 Tests

**Fichier**: `spec/lib/publipostage_civilite_normalization_spec.rb`

**16 tests créés** couvrant :
- ✅ Normalisation M./M → Monsieur
- ✅ Normalisation Mme/Mlle → Madame
- ✅ Civilités déjà longues restent inchangées
- ✅ Structures imbriquées (Hash, Array, complexes)
- ✅ Préservation des autres valeurs
- ✅ Préservation des types (Integer, Boolean, Date)

**Résultat** : 16 examples, 0 failures ✅

---

## 📊 Impact en production

### Avant Solution 2
- **45 documents régénérés** automatiquement
- Instructeurs voient de nouvelles versions
- Risque de confusion

### Avec Solution 2 ✅
- **0 documents régénérés** pour changement de civilité seule
- Documents régénérés **uniquement** si autres données changent
- Déploiement transparent

---

## 🔍 Scénarios testés

### Scénario 1 : Civilité seule change
```ruby
# Anciennes données (enregistrées)
{ 'demandeur' => { 'civilite' => 'M.', 'nom' => 'Dupont' } }

# Nouvelles données (après déploiement)
{ 'demandeur' => { 'civilite' => 'Monsieur', 'nom' => 'Dupont' } }

# Normalisation
old_normalized: { 'demandeur' => { 'civilite' => 'Monsieur', 'nom' => 'Dupont' } }
new_normalized: { 'demandeur' => { 'civilite' => 'Monsieur', 'nom' => 'Dupont' } }

# Résultat
IDENTIQUE → Document NON régénéré ✅
```

### Scénario 2 : Civilité ET autre donnée changent
```ruby
# Anciennes données
{ 'demandeur' => { 'civilite' => 'M.', 'nom' => 'Dupont' } }

# Nouvelles données
{ 'demandeur' => { 'civilite' => 'Monsieur', 'nom' => 'Martin' } }

# Normalisation
old_normalized: { 'demandeur' => { 'civilite' => 'Monsieur', 'nom' => 'Dupont' } }
new_normalized: { 'demandeur' => { 'civilite' => 'Monsieur', 'nom' => 'Martin' } }

# Résultat
DIFFÉRENT → Document régénéré (normal) ✅
```

### Scénario 3 : Aucun changement
```ruby
# Anciennes données
{ 'demandeur' => { 'civilite' => 'M.', 'nom' => 'Dupont' } }

# Nouvelles données (robot passe à nouveau)
{ 'demandeur' => { 'civilite' => 'M.', 'nom' => 'Dupont' } }

# Normalisation
old_normalized: { 'demandeur' => { 'civilite' => 'Monsieur', 'nom' => 'Dupont' } }
new_normalized: { 'demandeur' => { 'civilite' => 'Monsieur', 'nom' => 'Dupont' } }

# Résultat
IDENTIQUE → Document NON régénéré (déjà le cas) ✅
```

---

## 🚀 Plan de déploiement révisé

### Avant (sans Solution 2)
1. Tests staging
2. Communication instructeurs (45 régénérations)
3. Déploiement production
4. Surveillance intensive

### Maintenant (avec Solution 2) ✅
1. Tests staging (vérifier normalisation fonctionne)
2. ✅ **Pas de communication nécessaire** (zéro impact)
3. Déploiement production
4. Surveillance légère

---

## ⚠️ Points d'attention

### 1. Première génération APRÈS déploiement
Les **nouveaux documents** (première génération) utiliseront "Monsieur/Madame" :
- ✅ C'est le comportement souhaité
- ✅ Aucun document existant n'est touché

### 2. Modification manuelle d'un dossier
Si un instructeur modifie un dossier déjà généré :
- Le robot compare avec les données normalisées
- Si seule la civilité a "changé" (M. → Monsieur) → pas de régénération
- Si autre chose a changé → régénération normale

### 3. Durée de vie de la Solution 2
Cette solution est **permanente** et bénéfique :
- ✅ Évite les régénérations parasites lors de futurs changements de format
- ✅ Robustesse accrue du système de comparaison
- ✅ Aucun impact négatif

**Pas besoin de la retirer** - elle peut rester indéfiniment.

---

## 📝 Logs de déploiement

### Messages attendus dans les logs

**Avec Solution 2** :
```
Canceling publipost as input data coming from dossier is the same as before
```

**Sans Solution 2** (ce qui aurait été) :
```
BaserowSync: 1 nouveau(x) fichier(s) à uploader pour le champ Demandeur
Regenerating document 'Formulaire' due to 1 change(s):
  [demandeur.civilite] "M." → "Monsieur"
```

---

## ✅ Validation

### Tests manuels en staging

1. **Créer un dossier test avec civilité "M."**
2. **Générer un premier document** → Document créé avec "M."
3. **Déployer la nouvelle version** (M. → Monsieur dans le code)
4. **Relancer le robot sur ce dossier**
5. **Vérifier** : Document NON régénéré ✅
6. **Modifier une autre donnée** (ex: nom)
7. **Relancer le robot**
8. **Vérifier** : Document régénéré avec "Monsieur" (nouveau format) ✅

---

## 🎉 Résultat final

### Impact en production

| Métrique | Sans Solution 2 | Avec Solution 2 ✅ |
|----------|----------------|-------------------|
| Documents régénérés | 45 | **0** |
| Communication requise | Oui | **Non** |
| Surveillance | Intensive | Légère |
| Risque confusion | Moyen | **Aucun** |
| Effort déploiement | Élevé | **Faible** |

### Bénéfices

✅ **Déploiement transparent** - Zéro impact sur les 45 dossiers en cours
✅ **Pas de régénération parasite** - Documents stables
✅ **Solution pérenne** - Robustesse accrue du système
✅ **Tests complets** - 16 tests pour garantir le comportement
✅ **Code propre** - Rubocop compliant

---

## 📋 Checklist finale

- [x] Code implémenté dans `app/lib/publipostage.rb`
- [x] Méthode `normalize_civilites_in_data` créée
- [x] Méthode `normalize_civilite_value` créée
- [x] Comparaison modifiée dans `already_generated?`
- [x] 16 tests créés et passants
- [x] Rubocop compliant
- [x] Documentation complète
- [ ] Tests manuels en staging
- [ ] Déploiement en production
- [ ] Surveillance post-déploiement

---

**Statut** : ✅ **PRÊT POUR STAGING**

La Solution 2 est complètement implémentée, testée et prête à être déployée.
Les 45 documents en production ne seront PAS régénérés lors du déploiement.
