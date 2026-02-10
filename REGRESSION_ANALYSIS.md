# Rapport d'Analyse des Risques de Régression - dev → master

**Date**: 2026-02-10
**Commits analysés**: 20 commits entre master et dev
**Fichiers modifiés**: ~50 fichiers

---

## ⚠️ RISQUES CRITIQUES - IMPACT ÉLEVÉ

### 1. **Transformation des civilités dans FieldChecker** 🔴 CRITIQUE
**Fichier**: `app/lib/field_checker.rb`
**Commit**: `7d4eac8 - feat(field_checker): transformation civilités courtes en formes longues`

**Changement**:
```ruby
# AVANT (master)
when 'CiviliteChamp'
  champ.value.to_s  # Retourne "M.", "Mme"

# APRÈS (dev)
when 'CiviliteChamp'
  expand_civilite(champ.value.to_s)  # Retourne "Monsieur", "Madame"
```

**Impact**:
- ✅ **Positif**: Documents plus formels et professionnels
- ⚠️ **Risque**: TOUS les publipostages existants vont changer
- ⚠️ **Risque**: Documents Word/PDF générés différemment
- ⚠️ **Risque**: Possibles problèmes de mise en page si les templates sont dimensionnés pour "M."/"Mme"
- ⚠️ **Risque**: Validation de chaînes de caractères qui cherchent "M." ou "Mme"

**Modules affectés**:
- Publipostage (V1, V2, V3)
- Tous les SetAnnotationValue utilisant des civilités
- Tous les calculs/validations basés sur civilités
- Messages automatiques avec civilités

**Recommandation**:
- ⚠️ **TESTER TOUS LES PUBLIPOSTAGES** en staging avant production
- Vérifier les templates Word pour s'assurer qu'ils gèrent bien "Monsieur"/"Madame"
- Vérifier les configs YAML qui font des comparaisons sur civilités

---

### 2. **Interpolation dans blocs répétables PublipostageV2** 🟠 MOYEN-ÉLEVÉ
**Fichier**: `app/lib/publipostage_v2.rb`
**Commit**: Changements récents

**Changement**:
- Ajout de `interpolate_row_values()` qui permet maintenant d'utiliser `{champ}` au sein d'un bloc répétable
- Les valeurs string sont maintenant interpolées avec le contexte de la ligne

**Impact**:
- ✅ **Positif**: Nouvelle fonctionnalité puissante (références croisées dans blocs répétables)
- ⚠️ **Risque**: Si des champs contenaient `{quelquechose}` de manière littérale, cela sera maintenant interprété
- ⚠️ **Risque**: Performance potentiellement impactée (interpolation récursive)

**Exemple de risque**:
```yaml
# Si un champ contient littéralement "{montant}" comme texte
# AVANT: affiche "{montant}"
# APRÈS: tente d'interpoler et remplace par la valeur du champ "montant"
```

**Recommandation**:
- Vérifier les données métier pour des accolades `{...}` qui ne sont pas des variables
- Tester les blocs répétables existants

---

### 3. **CopyFileField: convert_to_pdf par défaut** 🟠 MOYEN
**Fichier**: `app/lib/copy_file_field.rb`
**Commit**: `45198a1 - feat(copy): ajout option convert_to_pdf et fix accumulation fichiers`

**Changement**:
```ruby
# Nouveau paramètre avec défaut à TRUE
convert = params.fetch(:convert_to_pdf, true)
```

**Impact**:
- ✅ **Positif**: Option pour copier sans conversion
- ⚠️ **Risque**: Comportement par défaut INCHANGÉ (toujours convertit en PDF)
- ⚠️ **Risque**: Nouvelles configurations doivent expliciter `convert_to_pdf: false` si besoin

**Recommandation**:
- Aucun impact sur configs existantes (comportement identique)
- Documenter le nouveau paramètre pour les nouvelles configs

---

### 4. **DAF CopyOrder: convert_to_pdf par défaut FALSE** 🟡 FAIBLE-MOYEN
**Fichier**: `app/lib/daf/copy_order.rb`
**Commit**: `45198a1`

**Changement**:
```ruby
# COMPORTEMENT CHANGÉ : par défaut FALSE
convert = params.fetch(:convert_to_pdf, false)
```

**Impact**:
- ⚠️ **RISQUE MAJEUR**: Les configurations DAF existantes ne convertiront PLUS en PDF par défaut
- ⚠️ Les images ne sont PLUS converties automatiquement
- ✅ Meilleure performance (pas de conversion inutile)

**Recommandation**:
- 🔴 **VÉRIFIER TOUTES LES CONFIGS DAF** qui utilisent `daf/copy_order`
- Ajouter explicitement `convert_to_pdf: true` si nécessaire
- Tester les workflows DAF en staging

---

## 🟡 RISQUES MODÉRÉS

### 5. **PublipostageV3: Support Markdown et images** 🟡 MOYEN
**Fichier**: `app/lib/publipostage_v3.rb`
**Commit**: `897310c`

**Changement**:
- Ajout du support Markdown dans ReferentielDePolynesie
- Ajout du lazy loading pour images et Excel
- Configuration Sablon pour styles français

**Impact**:
- ✅ Nouvelles fonctionnalités sans impact sur V1/V2
- ⚠️ Changement de comportement uniquement pour `publipostage_v3`
- ⚠️ Risque si migration de V2 vers V3

**Recommandation**:
- Pas d'impact sur les configs existantes (V1/V2)
- Tester les nouvelles configs V3

---

### 6. **Baserow: Synchronisation automatique** 🟢 FAIBLE
**Fichiers**: Module `MesDemarchesToBaserow`
**Commits**: Plusieurs commits Baserow

**Changement**:
- Ajout d'un système complet de synchronisation Baserow
- Nouveau module avec ~1500 lignes de code

**Impact**:
- ✅ Nouveau module isolé, pas d'impact sur l'existant
- ✅ Tests complets ajoutés et CI verte
- ⚠️ Nouvelle dépendance à l'API Baserow

**Recommandation**:
- Aucun risque pour les configs existantes
- Tester les nouvelles configs Baserow en staging

---

### 7. **Amélioration logging et comparaison dans Publipostage** 🟢 FAIBLE
**Fichier**: `app/lib/publipostage.rb`

**Changement**:
- Meilleure comparaison via JSON pour détecter les changements
- Logging détaillé des différences

**Impact**:
- ✅ Amélioration de la détection de changements
- ⚠️ Possible régénération de documents si la détection était trop permissive avant

**Recommandation**:
- Surveiller les logs pour voir si des documents sont régénérés plus souvent

---

### 8. **QRCode: Nouvelle fonctionnalité** 🟢 TRÈS FAIBLE
**Fichiers**: `qrcode.rb`, `qrcode_field.rb`, `qrcode_cache.rb`
**Commit**: `fbb9cb5`

**Changement**:
- Nouveau module pour générer des QR codes dans publipostage

**Impact**:
- ✅ Nouveau module isolé
- ✅ Aucun impact sur l'existant

---

## 📋 CHECKLIST DE DÉPLOIEMENT

### Avant déploiement en staging

- [ ] **Backup complet de la base de données production**
- [ ] **Export de toutes les configurations YAML actuelles**
- [ ] **Liste de tous les publipostages actifs**

### Tests obligatoires en staging

#### Tests Civilités (CRITIQUE)
- [ ] Tester TOUS les publipostages qui utilisent des champs civilité
- [ ] Vérifier visuellement les documents générés
- [ ] Vérifier que les templates Word supportent "Monsieur"/"Madame" (longueur)
- [ ] Tester les validations/calculs qui utilisent civilités

#### Tests DAF CopyOrder (CRITIQUE)
- [ ] Tester toutes les configs `daf/copy_order`
- [ ] Vérifier que les fichiers sont bien traités (PDF ou originaux)
- [ ] Ajouter `convert_to_pdf: true` si nécessaire

#### Tests PublipostageV2 (IMPORTANT)
- [ ] Tester tous les blocs répétables
- [ ] Vérifier qu'aucun texte littéral `{...}` n'est interpolé par erreur
- [ ] Tester les performances (temps de génération)

#### Tests généraux
- [ ] Exécuter la suite complète de tests (`bundle exec rspec`)
- [ ] Vérifier les logs pour des warnings/erreurs
- [ ] Tester les workflows les plus critiques de chaque direction

### Déploiement progressif recommandé

1. **Staging**: Déployer et tester pendant 2-3 jours
2. **Production limitée**: Activer sur 1-2 démarches non critiques
3. **Surveillance**: Monitorer les logs pendant 24h
4. **Production complète**: Si aucun problème détecté

---

## 🔍 CONFIGURATIONS À VÉRIFIER SPÉCIFIQUEMENT

### Fichiers YAML à auditer

```bash
# Rechercher les configs qui utilisent des civilités
grep -r "Civilité" storage/configurations/*.yml

# Rechercher les configs daf/copy_order
grep -r "daf/copy_order" storage/configurations/*.yml

# Rechercher les blocs répétables dans publipostage_v2
grep -r "publipostage_v2" storage/configurations/*.yml
```

### Démarches prioritaires à tester

1. **DGAE** (dgae_investissement.yml) - Utilise civilités
2. **DAF** - Utilise copy_order
3. **Toute démarche avec publipostage_v2 et blocs répétables**

---

## 📊 SYNTHÈSE DES RISQUES

| Risque | Impact | Probabilité | Mitigation |
|--------|--------|-------------|------------|
| Civilités changées dans tous les docs | 🔴 Élevé | 🔴 Certain | Tests exhaustifs staging |
| DAF copy_order sans conversion PDF | 🔴 Élevé | 🟠 Moyen | Audit configs + tests |
| Interpolation blocs répétables | 🟠 Moyen | 🟡 Faible | Tests ciblés |
| CopyFileField comportement | 🟢 Faible | 🟢 Très faible | Aucun (compatible) |
| Baserow sync | 🟢 Faible | 🟢 Très faible | Tests nouvelles configs |
| QRCode | 🟢 Très faible | 🟢 Aucun | Aucun (nouveau) |

---

## ✅ RECOMMANDATION FINALE

**Déploiement**: ✅ **AUTORISÉ AVEC PRÉCAUTIONS**

La branche `dev` contient des améliorations significatives mais introduit **2 changements de comportement critiques** :

1. 🔴 **Transformation automatique des civilités** : Impact garanti sur tous les publipostages
2. 🔴 **DAF CopyOrder ne convertit plus en PDF par défaut** : Risque de régression sur workflows DAF

### Plan d'action recommandé

1. **Phase de test staging (3-5 jours)**:
   - Tests exhaustifs des publipostages avec civilités
   - Audit et correction des configs DAF
   - Tests des blocs répétables

2. **Corrections préalables**:
   - Ajouter `convert_to_pdf: true` dans toutes les configs DAF qui en ont besoin
   - Vérifier tous les templates Word pour la longueur "Monsieur"/"Madame"

3. **Déploiement progressif**:
   - Commencer par des démarches non critiques
   - Monitorer les logs intensivement
   - Préparer un rollback rapide si nécessaire

4. **Communication**:
   - Informer les équipes métier du changement de civilités
   - Documenter les nouveaux paramètres pour les futures configs

**Effort estimé de migration**: 2-3 jours de tests + corrections configs
