#!/usr/bin/env python3
"""
Script pour trouver les sections manquantes
"""

import pandas as pd
import csv

# Charger toutes les sections du fichier Excel
df = pd.read_excel('Nomenclature ICPE.xlsx', header=None)
excel_sections = set()

for i in range(len(df)):
    col1 = df.iloc[i, 0]
    if pd.notna(col1) and isinstance(col1, (int, float)):
        excel_sections.add(int(col1))

print(f"Sections dans Excel : {len(excel_sections)}")

# Charger les sections du CSV transformé
csv_sections = set()
with open('nomenclature_icpe_transformed_v2.csv', 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        csv_sections.add(int(row['numero']))

print(f"Sections dans CSV transformé : {len(csv_sections)}")

# Trouver les sections manquantes
missing = excel_sections - csv_sections
if missing:
    print(f"\nSections manquantes dans le CSV transformé : {sorted(missing)}")
    
    # Trouver ces sections dans le fichier Excel
    for i in range(len(df)):
        col1 = df.iloc[i, 0]
        if pd.notna(col1) and isinstance(col1, (int, float)) and int(col1) in missing:
            col2 = df.iloc[i, 1] if len(df.columns) > 1 else ""
            col3 = df.iloc[i, 2] if len(df.columns) > 2 else ""
            print(f"\nLigne {i+1}: Section {int(col1)}")
            print(f"  Col2: {col2}")
            print(f"  Col3: {col3}")
else:
    print("\nAucune section manquante !")