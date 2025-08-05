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
        self.context_markers = {}  # Pour stocker les marqueurs de contexte (A, B, 1, 2, a, b, etc.)
        self.anomalies = []  # Pour stocker les anomalies détectées
        
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
    
    def is_context_line(self, text: str) -> Tuple[bool, int, str, str]:
        """
        Détermine si une ligne est un contexte numéroté et retourne le niveau
        Returns: (is_context, level, clean_text, marker)
        - level 1: A -, B -, C -, etc. (lettres majuscules)
        - level 2: 1), 2), 3-, etc. (chiffres)
        - level 3: a), b), c), etc. (lettres minuscules)
        """
        if pd.isna(text) or not isinstance(text, str):
            return False, 0, "", ""
            
        text = str(text).strip()
        
        # Niveau 1: A -, B -, C -, etc. (lettres majuscules)
        match = re.match(r'^([A-Z])\s*[-)]', text)
        if match:
            marker = match.group(1)
            clean_text = re.sub(r'^[A-Z]\s*[-)\s]+', '', text)
            return True, 1, clean_text, marker
        
        # Niveau 2: 1), 2), 3-, etc. (chiffres)
        match = re.match(r'^([0-9]+)\s*[\)\-]', text)
        if match:
            marker = match.group(1)
            clean_text = re.sub(r'^[0-9]+\s*[\)\-\s]+', '', text)
            return True, 2, clean_text, marker
        
        # Niveau 3: a), b), c), etc. (lettres minuscules)
        match = re.match(r'^([a-z]+)\)', text)
        if match:
            marker = match.group(1)
            clean_text = re.sub(r'^[a-z]+\)\s*', '', text)
            return True, 3, clean_text, marker
        
        return False, 0, text, ""
    
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
            is_context, _, _, _ = self.is_context_line(text)
            return not is_context
        
        return False
    
    def _collect_continuations(self, start_idx: int, level: int) -> str:
        """Collecte toutes les continuations d'un contexte à partir de start_idx+1"""
        continuations = []
        i = start_idx + 1
        
        while i < len(self.df):
            if self.is_note_line(i):
                # C'est potentiellement une continuation
                text = str(self.df.iloc[i, 1]).strip()
                continuations.append(text)
                i += 1
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
    
    def _check_potential_missing_content(self, row_idx: int) -> bool:
        """
        Vérifie si une ligne avec classification pourrait avoir du contenu manquant
        Retourne True si une anomalie est détectée
        """
        if not self.has_classification(row_idx):
            return False
            
        # Vérifier si la ligne suivante pourrait être une continuation non capturée
        if row_idx + 1 < len(self.df):
            next_row = self.df.iloc[row_idx + 1]
            if pd.isna(next_row[0]) and pd.notna(next_row[1]) and pd.isna(next_row[2]):
                next_text = str(next_row[1]).strip()
                
                # Vérifier que ce n'est PAS un marqueur de contexte (qui indiquerait une nouvelle section)
                is_context, _, _, _ = self.is_context_line(next_text)
                if is_context:
                    return False  # C'est un nouveau contexte, pas une continuation
                
                # Si c'est une longue liste de substances/éléments sans marqueur de contexte
                if (',' in next_text and len(next_text) > 100) or \
                   ('et/ou' in next_text.lower()) or \
                   ('sels' in next_text.lower() and ',' in next_text):
                    self._detect_anomaly(
                        row_idx,
                        "CONTINUATION_MANQUANTE",
                        f"La ligne {row_idx + 2} semble contenir une liste de substances qui devrait être intégrée au contexte de la ligne {row_idx + 1}",
                        "HIGH"
                    )
                    return True
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
        
        # Marqueurs de contexte actuels
        current_marker_1 = None
        current_marker_2 = None
        current_marker_3 = None
        
        skip_until = -1  # Pour éviter de traiter les lignes de continuation
        
        for i in range(len(self.df)):
            if i < skip_until:
                continue
                
            row = self.df.iloc[i]
            col1, col2, col3 = row[0], row[1], row[2]
            
            
            # Ligne d'en-tête de section
            if self.is_section_header(i):
                # Sauvegarder les notes précédentes si applicable
                if current_section_num and current_notes:
                    self._add_notes_to_current_section(current_notes)
                
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
                current_context_1 = None
                current_context_2 = None
                current_context_3 = None
                current_notes = []
                last_context_level = None
                
                # Reset compteurs pour nouvelle section
                context_1_counter = 0
                context_2_counter = 0
                context_3_counter = 0
                
                # Reset marqueurs pour nouvelle section
                current_marker_1 = None
                current_marker_2 = None
                current_marker_3 = None
                
                # Si la section a directement une classification
                if self.has_classification(i):
                    classification = str(col3)
                    self._add_record(current_section_num, current_section_name, 
                                   current_context_1, current_context_2, current_context_3,
                                   context_1_counter, context_2_counter, context_3_counter,
                                   current_marker_1, current_marker_2, current_marker_3,
                                   classification, current_notes)
                    last_context_level = None
                
                continue
            
            # Ligne de contexte
            if pd.notna(col2):
                text = str(col2)
                is_context, level, clean_text, marker = self.is_context_line(text)
                
                if is_context:
                    # Collecter les continuations potentielles
                    continuations = self._collect_continuations(i, level)
                    if continuations:
                        # Calculer combien de lignes on doit sauter
                        j = i + 1
                        while j < len(self.df) and self.is_note_line(j):
                            j += 1
                        skip_until = j
                    
                    if level == 1:
                        context_1_counter += 1
                        current_context_1 = clean_text
                        if continuations:
                            current_context_1 += " " + continuations
                        current_marker_1 = marker
                        current_context_2 = None  # Reset niveaux inférieurs
                        current_context_3 = None
                        context_2_counter = 0  # Reset compteurs inférieurs
                        context_3_counter = 0
                        current_marker_2 = None  # Reset marqueurs inférieurs
                        current_marker_3 = None
                    elif level == 2:
                        context_2_counter += 1
                        current_context_2 = clean_text
                        if continuations:
                            current_context_2 += " " + continuations
                        current_marker_2 = marker
                        current_context_3 = None  # Reset niveau 3
                        context_3_counter = 0  # Reset compteur niveau 3
                        current_marker_3 = None  # Reset marqueur niveau 3
                    elif level == 3:
                        context_3_counter += 1
                        current_context_3 = clean_text
                        if continuations:
                            current_context_3 += " " + continuations
                        current_marker_3 = marker
                    
                    last_context_level = level
                    
                    # Vérifier si cette ligne de contexte a une classification
                    if self.has_classification(i):
                        # Vérifier les anomalies potentielles
                        self._check_potential_missing_content(i)
                        
                        classification = str(col3)
                        self._add_record(current_section_num, current_section_name,
                                       current_context_1, current_context_2, current_context_3,
                                       context_1_counter, context_2_counter, context_3_counter,
                                       current_marker_1, current_marker_2, current_marker_3,
                                       classification, current_notes)
                        # Ne pas réinitialiser last_context_level ici car il pourrait y avoir des continuations
                
                # Ligne potentielle de continuation de contexte ou note
                elif self.is_note_line(i):
                    # Les continuations sont déjà gérées par _collect_continuations
                    # Donc ici, c'est forcément une vraie note
                    if last_context_level is None:
                        current_notes.append(text)
                    
                    # Détecter les notes suspicieusement longues qui pourraient être des contextes mal formatés
                    if len(text) > 150 and ',' in text:
                        self._detect_anomaly(
                            i,
                            "NOTE_SUSPECTE",
                            f"Cette note est très longue ({len(text)} caractères) et contient des virgules. Pourrait être un contexte mal formaté.",
                            "LOW"
                        )
                
                # Ligne de définition/contexte sans numérotation
                else:
                    # Vérifier si cette ligne a une classification (cas des seuils/conditions)
                    if self.has_classification(i):
                        # Ajouter le contenu de cette ligne au contexte approprié avant de créer l'enregistrement
                        line_content = str(col2).strip()
                        
                        # Déterminer à quel niveau de contexte ajouter cette ligne
                        if current_context_3:
                            # Ajouter au contexte niveau 3
                            current_context_3 += " " + line_content
                        elif current_context_2:
                            # Ajouter au contexte niveau 2
                            current_context_2 += " " + line_content
                        elif current_context_1:
                            # Ajouter au contexte niveau 1
                            current_context_1 += " " + line_content
                        else:
                            # Pas de contexte existant, créer un contexte niveau 1
                            current_context_1 = line_content
                            context_1_counter = 1 if context_1_counter == 0 else context_1_counter
                        
                        classification = str(col3)
                        self._add_record(current_section_num, current_section_name,
                                       current_context_1, current_context_2, current_context_3,
                                       context_1_counter, context_2_counter, context_3_counter,
                                       current_marker_1, current_marker_2, current_marker_3,
                                       classification, current_notes)
                    else:
                        # Reset du contexte level car ce n'est ni un contexte ni une continuation
                        last_context_level = None
            
            # Ligne avec classification seulement (contexte précédent)
            elif self.has_classification(i):
                classification = str(col3)
                self._add_record(current_section_num, current_section_name,
                               current_context_1, current_context_2, current_context_3,
                               context_1_counter, context_2_counter, context_3_counter,
                               current_marker_1, current_marker_2, current_marker_3,
                               classification, current_notes)
                last_context_level = None
        
        print(f"Traitement terminé. {len(self.results)} enregistrements générés.")
    
    def _add_record(self, section_num: int, section_name: str, 
                   context_1: Optional[str], context_2: Optional[str], context_3: Optional[str],
                   context_1_num: int, context_2_num: int, context_3_num: int,
                   marker_1: Optional[str], marker_2: Optional[str], marker_3: Optional[str],
                   classification: str, notes: List[str]):
        """Ajoute un enregistrement aux résultats"""
        notes_text = " | ".join(notes) if notes else ""
        
        # Génération de l'ID numérique au format section-n1.n2.n3
        # Les compteurs commencent à 1 lorsqu'il y a un contexte, sinon 0
        level_1 = context_1_num if context_1_num > 0 else 0
        level_2 = context_2_num if context_2_num > 0 else 0  
        level_3 = context_3_num if context_3_num > 0 else 0
        
        id_parts = [str(section_num)]
        id_parts.append(f"{level_1}.{level_2}.{level_3}")
        record_id = "-".join(id_parts)
        
        # Génération de l'ID avec marqueurs (ex: A.1.a)
        marker_parts = []
        if marker_1:
            marker_parts.append(marker_1)
        if marker_2:
            marker_parts.append(marker_2)
        if marker_3:
            marker_parts.append(marker_3)
        marker_id = ".".join(marker_parts) if marker_parts else ""
        
        record = {
            'id': record_id,
            'id_marker': marker_id,
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
        
        fieldnames = ['id', 'id_marker', 'numero_section', 'nom_section', 'contexte_1', 'contexte_2', 'contexte_3', 'classe', 'notes']
        
        with open(self.output_file, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(self.results)
        
        print(f"Fichier CSV créé: {self.output_file}")
    
    def save_anomalies_report(self):
        """Sauvegarde un rapport des anomalies détectées"""
        if not self.anomalies:
            print("Aucune anomalie détectée.")
            return
            
        report_file = self.output_file.replace('.csv', '_anomalies.csv')
        print(f"\nSauvegarde du rapport d'anomalies dans {report_file}...")
        
        fieldnames = ['ligne', 'type', 'severity', 'description', 'contenu']
        
        with open(report_file, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            # Trier par ligne
            sorted_anomalies = sorted(self.anomalies, key=lambda x: x['ligne'])
            writer.writerows(sorted_anomalies)
        
        print(f"Rapport d'anomalies créé: {report_file}")
    
    def print_anomalies_summary(self):
        """Affiche un résumé des anomalies détectées"""
        if not self.anomalies:
            return
            
        print(f"\n🔍 ANOMALIES DÉTECTÉES: {len(self.anomalies)}")
        
        # Grouper par type
        by_type = {}
        for anomaly in self.anomalies:
            anomaly_type = anomaly['type']
            if anomaly_type not in by_type:
                by_type[anomaly_type] = []
            by_type[anomaly_type].append(anomaly)
        
        for anomaly_type, items in by_type.items():
            print(f"\n{anomaly_type}: {len(items)} cas")
            # Afficher les 3 premiers exemples
            for item in items[:3]:
                print(f"  - Ligne {item['ligne']}: {item['description'][:100]}...")
                if len(item['contenu']) > 0:
                    print(f"    Contenu: {item['contenu'][:80]}...")
            if len(items) > 3:
                print(f"  ... et {len(items) - 3} autres")
    
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
        transformer.save_anomalies_report()
        transformer.print_summary()
        transformer.print_anomalies_summary()
        
    except Exception as e:
        print(f"Erreur: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()