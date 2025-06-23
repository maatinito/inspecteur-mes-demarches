#!/usr/bin/env python3
"""
Script pour transformer le fichier 'Nomenclature ICPE.xlsx' en CSV structuré
"""

import pandas as pd
import re
import csv
from typing import List, Dict, Optional, Tuple

class ICPETransformer:
    def __init__(self, input_file: str, output_file: str = 'nomenclature_icpe_transformed.csv'):
        self.input_file = input_file
        self.output_file = output_file
        self.df = None
        self.results = []
        
    def load_excel(self):
        """Charge le fichier Excel"""
        print(f"Chargement du fichier {self.input_file}...")
        self.df = pd.read_excel(self.input_file, header=None)
        print(f"Fichier chargé: {self.df.shape[0]} lignes x {self.df.shape[1]} colonnes")
        
    def is_section_header(self, row_idx: int) -> bool:
        """Détermine si une ligne est un en-tête de section (commence par un numéro)"""
        if row_idx >= len(self.df):
            return False
        value = self.df.iloc[row_idx, 0]
        return pd.notna(value) and isinstance(value, (int, float))
    
    def is_context_line(self, text: str) -> Tuple[bool, int, str]:
        """
        Détermine si une ligne est un contexte numéroté et retourne le niveau
        Returns: (is_context, level, clean_text)
        - level 1: A -, B -, C -, etc. (lettres majuscules)
        - level 2: 1), 2), 3-, etc. (chiffres)
        - level 3: a), b), c), etc. (lettres minuscules)
        """
        if pd.isna(text) or not isinstance(text, str):
            return False, 0, ""
            
        text = str(text).strip()
        
        # Niveau 1: A -, B -, C -, etc. (lettres majuscules)
        if re.match(r'^[A-Z]\s*[-)]', text):
            clean_text = re.sub(r'^[A-Z]\s*[-)\s]+', '', text)
            return True, 1, clean_text
        
        # Niveau 2: 1), 2), 3-, etc. (chiffres)
        if re.match(r'^[0-9]+\s*[\)\-]', text):
            clean_text = re.sub(r'^[0-9]+\s*[\)\-\s]+', '', text)
            return True, 2, clean_text
        
        # Niveau 3: a), b), c), etc. (lettres minuscules)
        if re.match(r'^[a-z]+\)', text):
            clean_text = re.sub(r'^[a-z]+\)\s*', '', text)
            return True, 3, clean_text
        
        return False, 0, text
    
    def has_classification(self, row_idx: int) -> bool:
        """Vérifie si une ligne a une classification (3ème colonne remplie)"""
        if row_idx >= len(self.df):
            return False
        value = self.df.iloc[row_idx, 2]
        return pd.notna(value) and value not in ['Classe', 'nan']
    
    def is_note_line(self, row_idx: int) -> bool:
        """
        Détermine si une ligne est une note (seulement colonne 2 remplie, sans numérotation)
        """
        if row_idx >= len(self.df):
            return False
            
        col1 = self.df.iloc[row_idx, 0]
        col2 = self.df.iloc[row_idx, 1]
        col3 = self.df.iloc[row_idx, 2]
        
        # Note: colonne 1 vide, colonne 2 remplie, colonne 3 vide
        if pd.isna(col1) and pd.notna(col2) and pd.isna(col3):
            text = str(col2).strip()
            is_context, _, _ = self.is_context_line(text)
            return not is_context
        
        return False
    
    def process_file(self):
        """Traite le fichier Excel et génère les enregistrements CSV"""
        print("Traitement du fichier...")
        
        current_section_num = None
        current_section_name = None
        current_context_1 = None
        current_context_2 = None
        current_context_3 = None
        current_notes = []
        last_context_level = None  # Track the last context level to detect continuations
        
        # Compteurs pour générer les IDs séquentiels
        context_1_counter = 0
        context_2_counter = 0
        context_3_counter = 0
        
        for i in range(len(self.df)):
            row = self.df.iloc[i]
            col1, col2, col3 = row[0], row[1], row[2]
            
            # Ligne d'en-tête de section
            if self.is_section_header(i):
                # Sauvegarder les notes précédentes si applicable
                if current_section_num and current_notes:
                    self._add_notes_to_current_section(current_notes)
                
                current_section_num = int(col1)
                current_section_name = str(col2) if pd.notna(col2) else ""
                current_context_1 = None
                current_context_2 = None
                current_context_3 = None
                current_notes = []
                last_context_level = None
                
                # Reset compteurs pour nouvelle section
                context_1_counter = 0
                context_2_counter = 0
                context_3_counter = 0
                
                # Si la section a directement une classification
                if self.has_classification(i):
                    classification = str(col3)
                    self._add_record(current_section_num, current_section_name, 
                                   current_context_1, current_context_2, current_context_3,
                                   context_1_counter, context_2_counter, context_3_counter,
                                   classification, current_notes)
                    last_context_level = None
                
                continue
            
            # Ligne de contexte
            if pd.notna(col2):
                text = str(col2)
                is_context, level, clean_text = self.is_context_line(text)
                
                if is_context:
                    if level == 1:
                        context_1_counter += 1
                        current_context_1 = clean_text
                        current_context_2 = None  # Reset niveaux inférieurs
                        current_context_3 = None
                        context_2_counter = 0  # Reset compteurs inférieurs
                        context_3_counter = 0
                    elif level == 2:
                        context_2_counter += 1
                        current_context_2 = clean_text
                        current_context_3 = None  # Reset niveau 3
                        context_3_counter = 0  # Reset compteur niveau 3
                    elif level == 3:
                        context_3_counter += 1
                        current_context_3 = clean_text
                    
                    last_context_level = level
                    
                    # Vérifier si cette ligne de contexte a une classification
                    if self.has_classification(i):
                        classification = str(col3)
                        self._add_record(current_section_num, current_section_name,
                                       current_context_1, current_context_2, current_context_3,
                                       context_1_counter, context_2_counter, context_3_counter,
                                       classification, current_notes)
                        last_context_level = None
                
                # Ligne potentielle de continuation de contexte ou note
                elif self.is_note_line(i):
                    # Si on vient juste d'avoir un contexte, c'est probablement une continuation
                    if last_context_level is not None:
                        # C'est une continuation du contexte précédent
                        if last_context_level == 1 and current_context_1:
                            current_context_1 += " " + text
                        elif last_context_level == 2 and current_context_2:
                            current_context_2 += " " + text
                        elif last_context_level == 3 and current_context_3:
                            current_context_3 += " " + text
                    else:
                        # C'est une vraie note
                        current_notes.append(text)
                
                # Ligne de définition/contexte sans numérotation
                else:
                    # Reset du contexte level car ce n'est ni un contexte ni une continuation
                    last_context_level = None
            
            # Ligne avec classification seulement (contexte précédent)
            elif self.has_classification(i):
                classification = str(col3)
                self._add_record(current_section_num, current_section_name,
                               current_context_1, current_context_2, current_context_3,
                               context_1_counter, context_2_counter, context_3_counter,
                               classification, current_notes)
                last_context_level = None
        
        print(f"Traitement terminé. {len(self.results)} enregistrements générés.")
    
    def _add_record(self, section_num: int, section_name: str, 
                   context_1: Optional[str], context_2: Optional[str], context_3: Optional[str],
                   context_1_num: int, context_2_num: int, context_3_num: int,
                   classification: str, notes: List[str]):
        """Ajoute un enregistrement aux résultats"""
        notes_text = " | ".join(notes) if notes else ""
        
        # Génération de l'ID au format section-n1.n2.n3 (commence à 1, 0 = niveau absent)
        level_1 = context_1_num if context_1_num > 0 else 0
        level_2 = context_2_num if context_2_num > 0 else 0  
        level_3 = context_3_num if context_3_num > 0 else 0
        
        id_parts = [str(section_num)]
        id_parts.append(f"{level_1}.{level_2}.{level_3}")
        record_id = "-".join(id_parts)
        
        record = {
            'id': record_id,
            'numero_section': section_num,
            'nom_section': section_name,
            'contexte_1': context_1 or "",
            'contexte_2': context_2 or "",
            'contexte_3': context_3 or "",
            'classe': classification,
            'notes': notes_text
        }
        
        self.results.append(record)
    
    def _add_notes_to_current_section(self, notes: List[str]):
        """Ajoute les notes à tous les enregistrements de la section courante"""
        if not notes:
            return
            
        notes_text = " | ".join(notes)
        # Ajouter les notes aux enregistrements récents de la même section
        for record in reversed(self.results):
            if record['numero_section'] == self.results[-1]['numero_section']:
                if record['notes']:
                    record['notes'] += " | " + notes_text
                else:
                    record['notes'] = notes_text
            else:
                break
    
    def save_csv(self):
        """Sauvegarde les résultats en CSV"""
        print(f"Sauvegarde dans {self.output_file}...")
        
        fieldnames = ['id', 'numero_section', 'nom_section', 'contexte_1', 'contexte_2', 'contexte_3', 'classe', 'notes']
        
        with open(self.output_file, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(self.results)
        
        print(f"Fichier CSV créé: {self.output_file}")
    
    def print_summary(self):
        """Affiche un résumé des résultats"""
        print(f"\nRésumé:")
        print(f"- Nombre total d'enregistrements: {len(self.results)}")
        
        sections = set(r['numero_section'] for r in self.results)
        print(f"- Nombre de sections: {len(sections)}")
        
        with_context_1 = sum(1 for r in self.results if r['contexte_1'])
        with_context_2 = sum(1 for r in self.results if r['contexte_2'])
        with_context_3 = sum(1 for r in self.results if r['contexte_3'])
        with_notes = sum(1 for r in self.results if r['notes'])
        
        print(f"- Enregistrements avec contexte niveau 1: {with_context_1}")
        print(f"- Enregistrements avec contexte niveau 2: {with_context_2}")
        print(f"- Enregistrements avec contexte niveau 3: {with_context_3}")
        print(f"- Enregistrements avec notes: {with_notes}")
        
        # Afficher quelques exemples
        print(f"\nPremiers enregistrements:")
        for i, record in enumerate(self.results[:5]):
            print(f"{i+1}. Section {record['numero_section']}: {record['classe']}")
            if record['contexte_1']:
                print(f"   Contexte 1: {record['contexte_1'][:80]}...")
            if record['contexte_2']:
                print(f"   Contexte 2: {record['contexte_2'][:80]}...")
            if record['contexte_3']:
                print(f"   Contexte 3: {record['contexte_3'][:80]}...")


def main():
    """Fonction principale"""
    input_file = "Nomenclature ICPE.xlsx"
    output_file = "nomenclature_icpe_transformed.csv"
    
    transformer = ICPETransformer(input_file, output_file)
    
    try:
        transformer.load_excel()
        transformer.process_file()
        transformer.save_csv()
        transformer.print_summary()
        
    except Exception as e:
        print(f"Erreur: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()