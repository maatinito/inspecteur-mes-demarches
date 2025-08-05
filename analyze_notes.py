#!/usr/bin/env python3
"""
Script pour analyser les notes potentielles dans le fichier ICPE
"""

import pandas as pd

# Charger le fichier Excel
df = pd.read_excel('Nomenclature ICPE.xlsx', header=None)

# Filtrer les lignes où:
# - Colonne 1 est vide (nan)
# - Colonne 2 contient ':'
# - Colonne 3 est vide (nan)
# - Colonne 2 ne se termine pas par 'étant :'
potential_notes = []

for i in range(len(df)):
    col1, col2, col3 = df.iloc[i, 0], df.iloc[i, 1], df.iloc[i, 2]
    
    # Vérifier si c'est une ligne de note potentielle
    if pd.isna(col1) and pd.notna(col2) and pd.isna(col3):
        text = str(col2).strip()
        
        # Vérifier si le texte contient ':'
        if ':' in text:
            # Exclure ceux qui finissent par 'étant :'
            if not text.endswith('étant :'):
                potential_notes.append({
                    'ligne': i + 1,
                    'texte': text[:100] + '...' if len(text) > 100 else text
                })

# Afficher les résultats
print(f"Nombre de notes potentielles trouvées: {len(potential_notes)}\n")

# Grouper par début de texte pour identifier les patterns
patterns = {}
for note in potential_notes:
    # Extraire le pattern jusqu'au premier ':'
    pattern = note['texte'].split(':')[0] + ':'
    if pattern not in patterns:
        patterns[pattern] = []
    patterns[pattern].append(note)

# Afficher les patterns trouvés
print("Patterns de notes identifiés:")
for pattern, notes in sorted(patterns.items()):
    print(f"\n'{pattern}' - {len(notes)} occurrences")
    # Afficher les 3 premiers exemples
    for note in notes[:3]:
        print(f"  Ligne {note['ligne']}: {note['texte']}")