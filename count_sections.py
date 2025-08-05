#!/usr/bin/env python3
"""
Script pour compter les sections (lignes avec colonne 1 valuée) dans le fichier Excel
"""

import pandas as pd

# Charger le fichier Excel
df = pd.read_excel('Nomenclature ICPE.xlsx', header=None)

# Compter les lignes où la colonne 1 est non vide
sections_count = 0
sections_list = []

for i in range(len(df)):
    col1 = df.iloc[i, 0]
    col2 = df.iloc[i, 1] if len(df.columns) > 1 else None
    
    # Si la colonne 1 contient une valeur (numéro de section)
    if pd.notna(col1) and isinstance(col1, (int, float)):
        sections_count += 1
        section_num = int(col1)
        section_name = str(col2) if pd.notna(col2) else ""
        sections_list.append({
            'ligne': i + 1,
            'numero': section_num,
            'nom': section_name[:50] + '...' if len(section_name) > 50 else section_name
        })

print(f"Nombre total de sections (lignes avec colonne 1 valuée) : {sections_count}")
print(f"\nPremières 10 sections :")
for section in sections_list[:10]:
    print(f"  Ligne {section['ligne']}: Section {section['numero']} - {section['nom']}")

print(f"\nDernières 10 sections :")
for section in sections_list[-10:]:
    print(f"  Ligne {section['ligne']}: Section {section['numero']} - {section['nom']}")

# Vérifier s'il y a des doublons
numeros = [s['numero'] for s in sections_list]
unique_numeros = set(numeros)
if len(numeros) != len(unique_numeros):
    print(f"\nATTENTION : Il y a des numéros de section en double !")
    from collections import Counter
    duplicates = {num: count for num, count in Counter(numeros).items() if count > 1}
    for num, count in duplicates.items():
        print(f"  Section {num} apparaît {count} fois")
else:
    print(f"\nTous les numéros de section sont uniques.")