#!/usr/bin/env Rscript

# Script pour créer 4 fichiers CSV relationnels pour Baserow
# Structure normalisée : Chapitres -> Groupes -> Catégories -> Codes

library(refpmsi)
library(dplyr)
library(readr)

cat("=== EXTRACTION CIM-10 RELATIONNELLE POUR BASEROW ===\n\n")

# Charger toutes les données
cat("1. Chargement des données...\n")
cim_data <- refpmsi::refpmsi(cim, 2024)
chapitres_data <- refpmsi::refpmsi(cim_chapitre, 2025)
groupes_data <- refpmsi::refpmsi(cim_groupe, 2025)

# ====================
# TABLE 1: CHAPITRES
# ====================
cat("\n2. Création de la table CHAPITRES...\n")

chapitres_table <- chapitres_data %>%
  select(
    chapitre_id = cim_chapitre_no,
    chapitre_libelle = cim_chapitre_libelle
  ) %>%
  mutate(
    chapitre_id = as.character(chapitre_id),
    chapitre_libelle = trimws(chapitre_libelle),
    chapitre_libelle = gsub('"', '""', chapitre_libelle)
  )

write_csv(chapitres_table, "cim10_chapitres.csv", na = "")
cat("   -> cim10_chapitres.csv créé (", nrow(chapitres_table), "enregistrements)\n")

# ====================
# TABLE 2: GROUPES
# ====================
cat("\n3. Création de la table GROUPES...\n")

# Créer mapping chapitre -> groupe à partir des données CIM
chapitre_groupe_mapping <- cim_data %>%
  select(cim_chapitre, cim_groupe) %>%
  filter(!is.na(cim_groupe)) %>%
  distinct() %>%
  rename(chapitre_id = cim_chapitre, groupe_code = cim_groupe)

groupes_table <- groupes_data %>%
  select(
    groupe_code = cim_groupe,
    groupe_libelle = cim_groupe_libelle
  ) %>%
  left_join(chapitre_groupe_mapping, by = "groupe_code") %>%
  select(
    groupe_code,
    groupe_libelle, 
    chapitre_id
  ) %>%
  mutate(
    groupe_code = trimws(groupe_code),
    groupe_libelle = trimws(groupe_libelle),
    groupe_libelle = gsub('"', '""', groupe_libelle),
    chapitre_id = as.character(chapitre_id)
  )

write_csv(groupes_table, "cim10_groupes.csv", na = "")
cat("   -> cim10_groupes.csv créé (", nrow(groupes_table), "enregistrements)\n")

# ====================
# TABLE 3: CATEGORIES
# ====================
cat("\n4. Création de la table CATEGORIES...\n")

categories_table <- cim_data %>%
  select(cim_categorie, cim_groupe) %>%
  filter(!is.na(cim_categorie)) %>%
  distinct() %>%
  rename(
    categorie_code = cim_categorie,
    groupe_code = cim_groupe
  ) %>%
  mutate(
    categorie_code = trimws(categorie_code),
    groupe_code = trimws(groupe_code)
  )

write_csv(categories_table, "cim10_categories.csv", na = "")
cat("   -> cim10_categories.csv créé (", nrow(categories_table), "enregistrements)\n")

# ====================
# TABLE 4: CODES CIM-10
# ====================
cat("\n5. Création de la table CODES...\n")

codes_table <- cim_data %>%
  # Garder la version la plus récente
  group_by(cim_code) %>%
  arrange(desc(annee_pmsi)) %>%
  filter(row_number() == 1) %>%
  ungroup() %>%
  select(
    code_cim = cim_code,
    libelle = cim_libelle,
    categorie_code = cim_categorie,
    precision = cim_precision,
    annee = annee_pmsi
  ) %>%
  mutate(
    code_cim = trimws(code_cim),
    libelle = trimws(libelle),
    libelle = gsub('"', '""', libelle),
    libelle = gsub('\n|\r', ' ', libelle),
    categorie_code = trimws(categorie_code)
  ) %>%
  arrange(code_cim)

write_csv(codes_table, "cim10_codes.csv", na = "")
cat("   -> cim10_codes.csv créé (", nrow(codes_table), "enregistrements)\n")

# ====================
# STATISTIQUES ET APERÇU
# ====================
cat("\n=== RÉSUMÉ DES FICHIERS CRÉÉS ===\n")
cat("1. cim10_chapitres.csv  :", nrow(chapitres_table), "chapitres\n")
cat("2. cim10_groupes.csv    :", nrow(groupes_table), "groupes\n") 
cat("3. cim10_categories.csv :", nrow(categories_table), "catégories\n")
cat("4. cim10_codes.csv      :", nrow(codes_table), "codes\n")

cat("\n=== APERÇU DES DONNÉES ===\n")

cat("\nCHAPITRES (échantillon):\n")
print(head(chapitres_table, 3))

cat("\nGROUPES (échantillon):\n")
print(head(groupes_table, 3))

cat("\nCATÉGORIES (échantillon):\n")
print(head(categories_table, 3))

cat("\nCODES (échantillon):\n")
print(head(codes_table, 3))

cat("\n=== RELATIONS BASEROW À CRÉER ===\n")
cat("1. Groupes.chapitre_id -> Chapitres.chapitre_id\n")
cat("2. Categories.groupe_code -> Groupes.groupe_code\n") 
cat("3. Codes.categorie_code -> Categories.categorie_code\n")

cat("\n✅ FICHIERS PRÊTS POUR IMPORTATION DANS BASEROW !\n")

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Cr\u00e9er table des chapitres CIM-10", "status": "completed", "activeForm": "Cr\u00e9ant la table des chapitres CIM-10"}, {"content": "Cr\u00e9er table des groupes CIM-10", "status": "in_progress", "activeForm": "Cr\u00e9ant la table des groupes CIM-10"}, {"content": "Cr\u00e9er table des cat\u00e9gories CIM-10", "status": "pending", "activeForm": "Cr\u00e9ant la table des cat\u00e9gories CIM-10"}, {"content": "Cr\u00e9er table des codes CIM-10 avec r\u00e9f\u00e9rences", "status": "pending", "activeForm": "Cr\u00e9ant la table des codes CIM-10 avec r\u00e9f\u00e9rences"}]