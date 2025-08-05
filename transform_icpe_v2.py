#!/usr/bin/env python3
"""
Script pour transformer le fichier 'Nomenclature ICPE.xlsx' en CSV structuré
Version 2 : Utilise une pile dynamique pour gérer les types de numérotations hétérogènes
"""

import pandas as pd
import re
import csv
from typing import List, Dict, Optional, Tuple
from enum import Enum

class NumberingType(Enum):
    UPPER_LETTER = "UPPER_LETTER"  # A, B, C...
    NUMBER = "NUMBER"              # 1, 2, 3...
    LOWER_LETTER = "LOWER_LETTER"  # a, b, c...

class ICPETransformerV2:
    def __init__(self, input_file: str, output_file: str = 'nomenclature_icpe_transformed_v2.csv'):
        self.input_file = input_file
        self.output_file = output_file
        self.df = None
        self.results = []
        self.anomalies = []
        self.sections = []  # Pour stocker les informations des sections
        
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
    
    def identify_numbering_type(self, text: str) -> Tuple[bool, NumberingType, str, str]:
        """
        Identifie le type de numérotation d'une ligne
        Returns: (is_numbering, type, clean_text, marker)
        """
        if pd.isna(text) or not isinstance(text, str):
            return False, None, "", ""
            
        text = str(text).strip()
        
        # Lettres majuscules: A -, B -, C -, etc.
        match = re.match(r'^([A-Z])\s*[-)]', text)
        if match:
            marker = match.group(1)
            clean_text = re.sub(r'^[A-Z]\s*[-)\s]+', '', text)
            return True, NumberingType.UPPER_LETTER, clean_text, marker
        
        # Chiffres: 1), 2), 3-, etc.
        match = re.match(r'^([0-9]+)\s*[\)\-]', text)
        if match:
            marker = match.group(1)
            clean_text = re.sub(r'^[0-9]+\s*[\)\-\s]+', '', text)
            return True, NumberingType.NUMBER, clean_text, marker
        
        # Lettres minuscules: a), b), c), etc.
        match = re.match(r'^([a-z]+)\)', text)
        if match:
            marker = match.group(1)
            clean_text = re.sub(r'^[a-z]+\)\s*', '', text)
            return True, NumberingType.LOWER_LETTER, clean_text, marker
        
        return False, None, text, ""
    
    def has_classification(self, row_idx: int) -> bool:
        """Vérifie si une ligne a une classification (3ème colonne remplie)"""
        if row_idx >= len(self.df):
            return False
        value = self.df.iloc[row_idx, 2]
        return pd.notna(value) and value not in ['Classe', 'nan']
    
    def is_note_trigger(self, text: str) -> bool:
        """
        Détermine si un texte est un déclencheur de note
        Les triggers peuvent être avec ou sans ':' et la recherche est heuristique
        """
        text_lower = text.lower()
        
        # Triggers de notes (insensible à la casse et avec/sans ':')
        note_triggers = [
            'nota',
            'exclus de cette rubrique',
            'sont exclus de cette rubrique',
            'sont compris dans cette rubrique'
        ]
        
        for trigger in note_triggers:
            if trigger in text_lower:
                return True
        
        return False
    
    def _collect_continuations(self, start_idx: int) -> str:
        """Collecte toutes les continuations à partir de start_idx+1"""
        continuations = []
        i = start_idx + 1
        
        while i < len(self.df):
            col1 = self.df.iloc[i, 0]
            col2 = self.df.iloc[i, 1]
            col3 = self.df.iloc[i, 2]
            
            # Ligne de continuation : col1 vide, col2 remplie, col3 vide
            if pd.isna(col1) and pd.notna(col2) and pd.isna(col3):
                text = str(col2).strip()
                
                # Vérifier que ce n'est ni une numérotation ni un trigger de note
                is_numbering, _, _, _ = self.identify_numbering_type(text)
                if not is_numbering and not self.is_note_trigger(text):
                    continuations.append(text)
                    i += 1
                else:
                    # C'est une numérotation ou un trigger de note, arrêter
                    break
            else:
                # Ce n'est plus une continuation
                break
                
        return " ".join(continuations) if continuations else ""
    
    def _detect_anomaly(self, row_idx: int, anomaly_type: str, description: str, severity: str = "WARNING"):
        """Enregistre une anomalie détectée"""
        row_num = row_idx + 1  # Numéro de ligne Excel (commence à 1)
        anomaly = {
            'ligne': row_num,
            'type': anomaly_type,
            'description': description,
            'severity': severity,
            'contenu': str(self.df.iloc[row_idx, 1]) if pd.notna(self.df.iloc[row_idx, 1]) else ""
        }
        self.anomalies.append(anomaly)
    
    def process_file(self):
        """Traite le fichier Excel et génère les enregistrements CSV"""
        print("Traitement du fichier avec la version 2 (pile dynamique)...")
        
        current_section_num = None
        current_section_name = None
        current_notes = []
        
        # Pile des types de numérotation et contextes correspondants
        numbering_stack = []  # Liste des NumberingType
        context_stack = []    # Liste des contextes correspondants
        marker_stack = []     # Liste des marqueurs correspondants
        counter_stack = []    # Liste des compteurs pour chaque niveau
        
        skip_until = -1  # Pour éviter de traiter les lignes de continuation
        has_seen_numbering_in_section = False  # Pour savoir si on a déjà vu une numérotation dans cette section
        is_collecting_notes = False  # Pour savoir si on est en train de collecter une note
        
        for i in range(len(self.df)):
            if i < skip_until:
                continue
                
            row = self.df.iloc[i]
            col1, col2, col3 = row[0], row[1], row[2]
            
            # Ligne d'en-tête de section
            if self.is_section_header(i):
                # Sauvegarder la section précédente avec ses notes
                if current_section_num:
                    self._save_section(current_section_num, current_section_name, current_notes)
                
                current_section_num = int(col1)
                current_section_name = str(col2) if pd.notna(col2) else ""
                
                # Détecter les sections sans nom
                if not current_section_name or len(current_section_name.strip()) == 0:
                    self._detect_anomaly(
                        i,
                        "SECTION_SANS_NOM",
                        f"La section {current_section_num} n'a pas de nom/description",
                        "WARNING"
                    )
                
                current_notes = []
                
                # Reset de la pile pour nouvelle section
                numbering_stack = []
                context_stack = []
                marker_stack = []
                counter_stack = []
                has_seen_numbering_in_section = False
                is_collecting_notes = False  # Arrêter la collecte de notes
                
                # Si la section a directement une classification
                if self.has_classification(i):
                    classification = str(col3)
                    self._add_record(current_section_num, current_section_name, 
                                   numbering_stack, context_stack, marker_stack, counter_stack,
                                   classification, current_notes)
                # Pas de else : on ne crée pas d'enregistrement pour les sections sans classification
                
                continue
            
            # Ligne de contexte
            if pd.notna(col2):
                text = str(col2)
                
                # Si on est en train de collecter des notes, ajouter à la note courante
                if is_collecting_notes:
                    current_notes.append(text)
                    continue
                
                # Vérifier si c'est un trigger de note
                if self.is_note_trigger(text):
                    is_collecting_notes = True
                    current_notes.append(text)
                    continue
                
                is_numbering, numbering_type, clean_text, marker = self.identify_numbering_type(text)
                
                if is_numbering:
                    has_seen_numbering_in_section = True  # Marquer qu'on a vu une numérotation
                    is_collecting_notes = False  # Arrêter la collecte de notes si on rencontre une numérotation
                    
                    # Collecter les continuations potentielles
                    continuations = self._collect_continuations(i)
                    if continuations:
                        # Calculer combien de lignes on doit sauter
                        j = i + 1
                        while j < len(self.df):
                            # Vérifier si c'est une ligne de continuation (pas de col1, col2 remplie, pas de col3)
                            if pd.isna(self.df.iloc[j, 0]) and pd.notna(self.df.iloc[j, 1]) and pd.isna(self.df.iloc[j, 2]):
                                j += 1
                            else:
                                break
                        skip_until = j
                    
                    # Gérer la pile de numérotation
                    try:
                        # Chercher si ce type existe déjà dans la pile
                        existing_level = numbering_stack.index(numbering_type)
                        # Le type existe, retourner à ce niveau
                        numbering_stack = numbering_stack[:existing_level + 1]
                        context_stack = context_stack[:existing_level + 1]
                        marker_stack = marker_stack[:existing_level + 1]
                        counter_stack = counter_stack[:existing_level + 1]
                        
                        # Incrémenter le compteur pour ce niveau
                        counter_stack[existing_level] += 1
                        
                        # Mettre à jour le contexte et le marqueur
                        full_text = clean_text
                        if continuations:
                            full_text += " " + continuations
                        context_stack[existing_level] = full_text
                        marker_stack[existing_level] = marker
                        
                    except ValueError:
                        # Le type n'existe pas, ajouter un nouveau niveau
                        numbering_stack.append(numbering_type)
                        full_text = clean_text
                        if continuations:
                            full_text += " " + continuations
                        context_stack.append(full_text)
                        marker_stack.append(marker)
                        counter_stack.append(1)  # Premier élément de ce niveau
                    
                    # Vérifier si cette ligne de contexte a une classification
                    if self.has_classification(i):
                        classification = str(col3)
                        self._add_record(current_section_num, current_section_name,
                                       numbering_stack, context_stack, marker_stack, counter_stack,
                                       classification, current_notes)
                
                # Ligne sans numérotation
                elif not has_seen_numbering_in_section:
                    # Pas encore vu de numérotation : c'est une continuation du nom de section
                    if current_section_name:
                        current_section_name += " " + text
                    else:
                        current_section_name = text
                
                # Ligne de définition/contexte sans numérotation
                else:
                    # Vérifier si cette ligne a une classification (cas des seuils/conditions)
                    if self.has_classification(i):
                        # Ajouter le contenu de cette ligne au contexte approprié avant de créer l'enregistrement
                        line_content = str(col2).strip()
                        
                        # Ajouter au dernier niveau de contexte, ou créer un niveau 1 si aucun contexte
                        if context_stack:
                            # Ajouter au contexte du niveau le plus profond
                            context_stack[-1] += " " + line_content
                        else:
                            # Pas de contexte existant, créer un niveau par défaut
                            # On ne peut pas déterminer le type, donc on utilise un marqueur spécial
                            numbering_stack.append(None)  # Type indéterminé
                            context_stack.append(line_content)
                            marker_stack.append("")
                            counter_stack.append(1)
                        
                        classification = str(col3)
                        self._add_record(current_section_num, current_section_name,
                                       numbering_stack, context_stack, marker_stack, counter_stack,
                                       classification, current_notes)
            
            # Ligne avec classification seulement (contexte précédent)
            elif self.has_classification(i):
                classification = str(col3)
                self._add_record(current_section_num, current_section_name,
                               numbering_stack, context_stack, marker_stack, counter_stack,
                               classification, current_notes)
        
        # Sauvegarder la dernière section
        if current_section_num:
            self._save_section(current_section_num, current_section_name, current_notes)
        
        print(f"Traitement terminé. {len(self.results)} enregistrements générés.")
    
    def _add_record(self, section_num: int, section_name: str, 
                   numbering_stack: List[NumberingType], context_stack: List[str], 
                   marker_stack: List[str], counter_stack: List[int],
                   classification: str, notes: List[str]):
        """Ajoute un enregistrement aux résultats"""
        # Les notes sont maintenant gérées au niveau section
        
        # Génération du chemin (numérotation standardisée)
        if counter_stack:
            chemin = ".".join(str(count) for count in counter_stack)
        else:
            chemin = "0"
        
        # Génération des numérotations (marqueurs)
        numerotations = ".".join([marker for marker in marker_stack if marker]) if marker_stack else ""
        
        # Génération de l'ID : numéro de section + tiret + numérotations si non vide
        if numerotations:
            record_id = f"{section_num}-{numerotations}"
        else:
            record_id = str(section_num)
        
        # Préparation des contextes (jusqu'à 3 niveaux max pour compatibilité)
        contexte_1 = context_stack[0] if len(context_stack) > 0 else ""
        contexte_2 = context_stack[1] if len(context_stack) > 1 else ""
        contexte_3 = context_stack[2] if len(context_stack) > 2 else ""
        
        # Si plus de 3 niveaux, concaténer les niveaux supplémentaires au niveau 3
        if len(context_stack) > 3:
            additional_contexts = " | ".join(context_stack[3:])
            contexte_3 += " | " + additional_contexts if contexte_3 else additional_contexts
        
        record = {
            'id': record_id,
            'numero': section_num,
            'chemin': chemin,
            'numerotations': numerotations,
            'nom_section': section_name,
            'contexte_1': contexte_1,
            'contexte_2': contexte_2,
            'contexte_3': contexte_3,
            'classe': classification,
            'pile_types': "|".join([nt.value if nt else "NONE" for nt in numbering_stack]),  # Debug
            'pile_depth': len(numbering_stack)  # Debug
        }
        
        self.results.append(record)
    
    def _save_section(self, section_num: int, section_name: str, notes: List[str]):
        """Sauvegarde les informations d'une section avec ses notes"""
        notes_text = " | ".join(notes) if notes else ""
        
        section = {
            'numero': section_num,
            'nom_section': section_name,
            'notes': notes_text
        }
        
        self.sections.append(section)
    
    def save_csv(self):
        """Sauvegarde les résultats en CSV"""
        print(f"Sauvegarde dans {self.output_file}...")
        
        fieldnames = ['id', 'numero', 'chemin', 'numerotations', 'nom_section', 'contexte_1', 'contexte_2', 'contexte_3', 'classe', 'pile_types', 'pile_depth']
        
        with open(self.output_file, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(self.results)
        
        print(f"Fichier CSV créé: {self.output_file}")
    
    def save_sections_csv(self):
        """Sauvegarde les sections avec leurs notes dans un fichier séparé"""
        sections_file = self.output_file.replace('.csv', '_sections.csv')
        print(f"Sauvegarde des sections dans {sections_file}...")
        
        fieldnames = ['numero', 'nom_section', 'notes']
        
        with open(sections_file, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(self.sections)
        
        print(f"Fichier des sections créé: {sections_file}")
    
    def save_anomalies_report(self):
        """Sauvegarde un rapport des anomalies détectées"""
        if not self.anomalies:
            print("Aucune anomalie détectée.")
            return
            
        report_file = self.output_file.replace('.csv', '_anomalies.csv')
        print(f"\\nSauvegarde du rapport d'anomalies dans {report_file}...")
        
        fieldnames = ['ligne', 'type', 'severity', 'description', 'contenu']
        
        with open(report_file, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            # Trier par ligne
            sorted_anomalies = sorted(self.anomalies, key=lambda x: x['ligne'])
            writer.writerows(sorted_anomalies)
        
        print(f"Rapport d'anomalies créé: {report_file}")
    
    def print_summary(self):
        """Affiche un résumé des résultats"""
        print(f"\\nRésumé VERSION 2:")
        print(f"- Nombre total d'enregistrements: {len(self.results)}")
        
        print(f"- Nombre de sections: {len(self.sections)}")
        
        with_context_1 = sum(1 for r in self.results if r['contexte_1'])
        with_context_2 = sum(1 for r in self.results if r['contexte_2'])
        with_context_3 = sum(1 for r in self.results if r['contexte_3'])
        with_notes = sum(1 for s in self.sections if s['notes'])
        
        print(f"- Enregistrements avec contexte niveau 1: {with_context_1}")
        print(f"- Enregistrements avec contexte niveau 2: {with_context_2}")
        print(f"- Enregistrements avec contexte niveau 3: {with_context_3}")
        print(f"- Sections avec notes: {with_notes}")
        
        # Analyse de la pile
        pile_depths = [r['pile_depth'] for r in self.results]
        max_depth = max(pile_depths) if pile_depths else 0
        min_depth = min(pile_depths) if pile_depths else 0
        avg_depth = sum(pile_depths) / len(pile_depths) if pile_depths else 0
        
        print(f"\\nAnalyse de la pile:")
        print(f"- Profondeur maximale: {max_depth}")
        print(f"- Profondeur minimale: {min_depth}")
        print(f"- Profondeur moyenne: {avg_depth:.2f}")
        
        # Compter les enregistrements sans contexte niveau 1 vide
        empty_context_1 = sum(1 for r in self.results if not r['contexte_1'])
        print(f"- Enregistrements avec contexte niveau 1 vide: {empty_context_1}")
        
        # Afficher quelques exemples
        print(f"\\nPremiers enregistrements:")
        for i, record in enumerate(self.results[:5]):
            print(f"{i+1}. ID: {record['id']}, Numéro: {record['numero']}, Chemin: {record['chemin']}, Numérotations: {record['numerotations']}")
            print(f"   Classe: {record['classe']} (Pile: {record['pile_depth']})")
            if record['contexte_1']:
                print(f"   Contexte 1: {record['contexte_1'][:80]}...")
            if record['contexte_2']:
                print(f"   Contexte 2: {record['contexte_2'][:80]}...")
            if record['contexte_3']:
                print(f"   Contexte 3: {record['contexte_3'][:80]}...")


def main():
    """Fonction principale"""
    input_file = "Nomenclature ICPE.xlsx"
    output_file = "nomenclature_icpe_transformed_v2.csv"
    
    transformer = ICPETransformerV2(input_file, output_file)
    
    try:
        transformer.load_excel()
        transformer.process_file()
        transformer.save_csv()
        transformer.save_sections_csv()
        transformer.save_anomalies_report()
        transformer.print_summary()
        
    except Exception as e:
        print(f"Erreur: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()