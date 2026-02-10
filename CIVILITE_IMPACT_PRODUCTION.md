# Analyse d'Impact - Civilités en Production

**Date**: 2026-02-10
**Source**: robot-mes-demarches-production/configurations/
**Changement**: M./Mme → Monsieur/Madame

---

## 📊 STATISTIQUES GLOBALES

- **Total fichiers YAML en production**: 58
- **Fichiers utilisant des civilités**: 24 (41%)
- **Fichiers actifs (hors /ignored/)**: 13
- **Fichiers archivés (/ignored/)**: 5
- **Fichiers SAV (/sav/)**: 6

---

## 🔴 IMPACT CRITIQUE - Usages dans Templates (set_field)

Ces fichiers utilisent des civilités dans des **templates interpolés** via `{civilite}`.
Le changement M./Mme → Monsieur/Madame **affectera directement** le texte généré.

### 1. **daf_tomite.yml** - DAF TOMITE
```yaml
set_field:
  champ: "Demandeur"
  valeur: "{demandeur.civilite} {demandeur.prenom} {demandeur.nom}"
```
**Impact**:
- Annotation "Demandeur" affichera "Monsieur Jean Dupont" au lieu de "M. Jean Dupont"
- ⚠️ **Vérifier la longueur du champ** dans l'interface

---

### 2. **dbs_laissez-passer.yml** - DBS Laissez-Passer
```yaml
set_field:
  champ: "Destinataire"
  valeur: |
    {Dossier.Civilité Destinataire} {Dossier.Prénom Destinataire} {Dossier.Nom Destinataire}
    {Dossier.Adresse Destinataire}

# ET aussi:
set_field:
  champ: "Destinataire"
  valeur: |
    {Civilité Destinataire} {Prénom Destinataire} {Nom Destinataire}
    {Adresse Destinataire}
```
**Impact**:
- Adresses destinataires avec civilités longues
- ⚠️ **Vérifier le formatage de l'adresse** dans les documents générés

---

### 3. **diren_signalements.yml** - DIREN Signalements
```yaml
set_field:
  champ: "Objet"
  valeur: "Signalement par {demandeur.civilite} {demandeur.prenom} {demandeur.nom}\nNuisance : {Type de nuisance}"
```
**Impact**:
- Champ "Objet" sera plus long
- Exemple: "Signalement par **Monsieur** Jean Dupont" au lieu de "Signalement par **M.** Jean Dupont"
- ⚠️ **Vérifier longueur maximale du champ "Objet"**

---

## 🟠 IMPACT MODÉRÉ - Colonnes Excel/CSV

Ces fichiers exportent des civilités dans des **colonnes Excel**.
Les valeurs dans les cellules changeront mais sans impact fonctionnel majeur.

### Fichiers DAF (États, Factures, Copies)
- **daf_copie_actes.yml**
- **daf_etats_hypothecaires.yml**
- **dgae_assureurs.yml**
- **sti_turama.yml**

```yaml
champs:
  - colonne: Civilité
    champ: 'demandeur.civilite'
```

**Impact**:
- Colonne "Civilité" dans Excel: "Monsieur" au lieu de "M."
- ✅ **Impact esthétique uniquement**, pas de problème fonctionnel
- ⚠️ Possible problème si des **formules Excel** cherchent "M." ou "Mme"

---

### Fichiers DBS (Laissez-passer, Pesticides)
- **dbs_laissez-passer.yml**
  - Colonne "Civilité déclarant"
  - Colonne "Civilité agent"
- **dbs_pesticides.yml**
  - Colonne "Civilité Destinataire"

**Impact**:
- Idem DAF, colonnes Excel plus larges
- ⚠️ **Vérifier les templates Excel** pour la largeur de colonne

---

### Fichiers DIREN (Contrôle, Signalements)
- **diren_controle.yml**
  - Colonne "Civilité agent" (3 occurrences)
  - Colonne "Civilité"
- **diren_signalements.yml**
  - Colonne "Civilité"

---

### Fichiers DTT (Examens)
- **dtt_examens.yml**
  - Colonne "Civilité" (2 occurrences)

---

### Fichiers G2P
- **g2p_reservation_site_lucratif.yml**
  - Liste "Civilité" (sans mapping)

---

## 🟢 IMPACT FAIBLE - Fichiers Ignorés/SAV

Ces fichiers sont dans `/ignored/` ou `/sav/` donc **probablement inactifs**.

### Fichiers ignorés
- dbs_phyto_laissez-passer.yml
- dbs_zoo_laissez-passer.yml
- sante_recrutement.yml
- sante_subventions.yml
- dbs_pesticides.yml (doublon)

### Fichiers SAV (Sauvegarde/Archive)
- sav/daf_copie_actes.yml
- sav/daf_etats_hypothecaires.yml
- sav/sante_subventions.yml
- sav/dbs_laissez-passer.yml (avec set_field)
- sav/daf_tomite.yml (avec set_field)
- sav/dbs_pesticides.yml
- sav/sti_turama.yml
- sav/dtt_examens.yml

---

## 📋 CHECKLIST DE TESTS EN STAGING

### Tests Prioritaires (CRITIQUE)

#### 1. DAF TOMITE
- [ ] Créer un dossier test avec civilité M.
- [ ] Vérifier annotation "Demandeur" = "Monsieur [Prénom] [Nom]"
- [ ] Vérifier que le champ n'est pas tronqué

#### 2. DBS Laissez-Passer
- [ ] Créer un dossier test Particulier
- [ ] Vérifier annotation "Destinataire" avec "Monsieur/Madame"
- [ ] Vérifier le formatage de l'adresse complète
- [ ] Tester avec Mme pour "Madame"

#### 3. DIREN Signalements
- [ ] Créer un signalement avec civilité
- [ ] Vérifier champ "Objet" avec "Signalement par Monsieur..."
- [ ] Vérifier qu'il n'y a pas de troncature

### Tests Secondaires (Colonnes Excel)

#### DAF - Exports Excel
- [ ] **daf_copie_actes**: Générer Excel, vérifier colonne "Civilité"
- [ ] **daf_etats_hypothecaires**: Idem
- [ ] **dgae_assureurs**: Idem
- [ ] **sti_turama**: Idem

#### DBS - Exports
- [ ] **dbs_laissez-passer**: Vérifier colonnes civilités dans Excel
- [ ] **dbs_pesticides**: Idem

#### DIREN - Exports
- [ ] **diren_controle**: Vérifier colonnes agents/civilités
- [ ] **diren_signalements**: Vérifier colonne civilité

#### DTT
- [ ] **dtt_examens**: Vérifier colonne civilité

---

## ⚠️ POINTS D'ATTENTION SPÉCIFIQUES

### 1. Longueurs de champs
**Avant**: "M." = 2 caractères, "Mme" = 3 caractères
**Après**: "Monsieur" = 8 caractères, "Madame" = 6 caractères

**Augmentation**: +6 caractères pour M., +3 pour Mme

**Fichiers à risque**:
- `daf_tomite.yml`: Champ "Demandeur" potentiellement limité
- `dbs_laissez-passer.yml`: Adresse sur plusieurs lignes (OK)
- `diren_signalements.yml`: Champ "Objet" - **vérifier limite caractères**

### 2. Templates Word/Excel
Si des templates Word ou Excel ont des **cellules/champs de taille fixe**, ils peuvent nécessiter un ajustement.

### 3. Formules Excel
Si des formules cherchent "M." ou "Mme", elles ne fonctionneront plus:
```excel
=SI(A1="M."; "Masculin"; "Féminin")  # ❌ Ne fonctionnera plus
```

### 4. Comparaisons dans configs YAML
Chercher si des configs font des comparaisons sur civilités:
```bash
grep -r "M\." robot-mes-demarches-production/configurations --include="*.yml"
grep -r "Mme" robot-mes-demarches-production/configurations --include="*.yml"
```

---

## 🎯 SYNTHÈSE PAR PRIORITÉ

### 🔴 URGENT - Tests obligatoires
1. **daf_tomite.yml** - Template set_field
2. **dbs_laissez-passer.yml** - Template set_field (adresse)
3. **diren_signalements.yml** - Template set_field (objet)

### 🟠 IMPORTANT - Vérification visuelle
1. Tous les exports Excel DAF/DBS/DIREN/DTT
2. Templates Word si utilisés
3. Largeurs de colonnes Excel

### 🟢 OPTIONNEL - Si temps disponible
1. Fichiers SAV (probablement inactifs)
2. Fichiers ignored

---

## 💡 RECOMMANDATIONS

### Option 1: Déploiement progressif (RECOMMANDÉ)
1. Déployer en staging
2. Tester les 3 fichiers CRITIQUES
3. Vérifier visuellement les exports Excel
4. Si OK → déployer en production
5. Surveiller les logs pendant 48h

### Option 2: Rollback partiel
Si problème détecté, possibilité de créer une version intermédiaire:
```ruby
def expand_civilite(value, short_form: false)
  return value if short_form

  case value
  when 'M.', 'M' then 'Monsieur'
  when 'Mme', 'Mlle' then 'Madame'
  else value
  end
end
```

Puis dans les configs problématiques, ajouter un flag temporaire.

### Option 3: Communication préalable
- Informer les services DAF, DBS, DIREN que les civilités seront en toutes lettres
- Demander validation des templates avant déploiement

---

## 📊 ESTIMATION IMPACT

**Fichiers ACTIFS impactés**: 13
- **Risque CRITIQUE**: 3 (set_field avec templates)
- **Risque MOYEN**: 10 (colonnes Excel)
- **Risque FAIBLE**: 11 (SAV/ignored)

**Effort de test**:
- Tests critiques: 1-2 heures
- Tests exports Excel: 2-3 heures
- **TOTAL**: 3-5 heures de tests en staging

**Probabilité de régression**:
- 🔴 **Esthétique**: 100% (changement garanti)
- 🟠 **Fonctionnelle**: 20% (si champs tronqués)
- 🟢 **Bloquante**: 5% (très peu probable)
