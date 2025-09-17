#!/usr/bin/env Rscript

# Script R COMPLET pour extraire CIM-10 avec TOUS les libellés de refpmsi
library(refpmsi)
library(dplyr)
library(readr)

cat("Chargement des données CIM-10 et de leurs libellés...\n")

# 1. Charger les données principales CIM-10
cim_data <- refpmsi::refpmsi(cim, 2024)
cat("Codes CIM-10 chargés:", nrow(cim_data), "enregistrements\n")

# 2. Charger les libellés des chapitres
chapitres <- refpmsi::refpmsi(cim_chapitre, 2025)
cat("Chapitres chargés:", nrow(chapitres), "enregistrements\n")

# 3. Charger les libellés des groupes
groupes <- refpmsi::refpmsi(cim_groupe, 2025)
cat("Groupes chargés:", nrow(groupes), "enregistrements\n")

# 4. Joindre toutes les données
cim_complet <- cim_data %>%
  # Garder la version la plus récente de chaque code
  group_by(cim_code) %>%
  arrange(desc(annee_pmsi)) %>%
  filter(row_number() == 1) %>%
  ungroup() %>%
  # Joindre les libellés des chapitres
  left_join(chapitres, by = c("cim_chapitre" = "cim_chapitre_no")) %>%
  # Joindre les libellés des groupes
  left_join(groupes, by = "cim_groupe") %>%
  # Sélectionner et renommer les colonnes
  select(
    code_cim = cim_code,
    libelle = cim_libelle,
    chapitre_no = cim_chapitre,
    chapitre_libelle = cim_chapitre_libelle,
    groupe_code = cim_groupe,
    groupe_libelle = cim_groupe_libelle,
    categorie = cim_categorie,
    precision = cim_precision,
    annee = annee_pmsi
  ) %>%
  # Nettoyer les données pour Baserow
  mutate(
    code_cim = trimws(code_cim),
    libelle = trimws(libelle),
    chapitre_libelle = trimws(chapitre_libelle),
    groupe_libelle = trimws(groupe_libelle),
    # Remplacer les caractères problématiques
    libelle = gsub('"', '""', libelle),
    libelle = gsub('\n|\r', ' ', libelle),
    chapitre_libelle = gsub('"', '""', chapitre_libelle),
    groupe_libelle = gsub('"', '""', groupe_libelle),
    categorie = trimws(categorie)
  ) %>%
  arrange(code_cim)

cat("Données complètes préparées:", nrow(cim_complet), "codes uniques\n")

# 5. Exporter vers CSV avec libellés complets
output_file <- "cim10_baserow_complet.csv"

write_csv(cim_complet, output_file, na = "")

cat("Export terminé:", output_file, "\n")
cat("Format: UTF-8, délimiteur virgule, avec TOUS les libellés\n")

# Afficher un aperçu
cat("\nAperçu des données complètes:\n")
print(head(cim_complet, 5))

# Statistiques détaillées
cat("\nStatistiques détaillées:\n")
cat("- Nombre total de codes CIM-10:", nrow(cim_complet), "\n")
cat("- Chapitres uniques:", length(unique(cim_complet$chapitre_no)), "\n")
cat("- Groupes uniques:", length(unique(cim_complet$groupe_code)), "\n") 
cat("- Catégories uniques:", length(unique(cim_complet$categorie)), "\n")
cat("- Années couvertes:", paste(sort(unique(cim_complet$annee)), collapse = ", "), "\n")
cat("- Fichier de sortie:", output_file, "\n")

# Exemples de libellés trouvés
cat("\nExemples de libellés complets trouvés:\n")
exemples <- cim_complet %>% 
  filter(!is.na(chapitre_libelle), !is.na(groupe_libelle)) %>%
  head(3) %>%
  select(code_cim, chapitre_libelle, groupe_libelle)
print(exemples)

cat("\nFichier CSV COMPLET prêt pour importation dans Baserow !\n")