#!/usr/bin/env python3
"""
Script d'extraction de toutes les variables d'un modèle Lexpol
Génère un fichier CSV avec toutes les variables et leurs informations
"""
import asyncio
import csv
from datetime import datetime
from playwright.async_api import async_playwright
import lexpol_config as config
from lexpol_connection import LexpolConnection


async def extract_variables(page):
    """
    Extrait toutes les variables du modèle Lexpol

    Returns:
        list: Liste de dictionnaires contenant les informations des variables
    """
    print("\n" + "="*80)
    print("📋 EXTRACTION DES VARIABLES")
    print("="*80 + "\n")

    # Récupérer toutes les variables
    variables = await page.query_selector_all('li[id^="variable"]')
    print(f"📊 Trouvé {len(variables)} variable(s)\n")

    variables_data = []

    for i, var_element in enumerate(variables, 1):
        try:
            # Récupérer tout le texte de l'élément variable
            full_text = await var_element.inner_text()

            # Extraire le code de la variable (entre {@...@})
            var_code_elem = await var_element.query_selector('.variableCodeLibelle')
            if not var_code_elem:
                continue

            code_text = await var_code_elem.inner_text()
            var_name = code_text.strip().replace('{@', '').replace('@}', '')

            # Le libellé est généralement affiché après le code
            # On essaie de l'extraire du texte complet en enlevant le code
            var_libelle = full_text.replace(code_text, '').strip()
            # Nettoyer les sauts de ligne et espaces multiples
            var_libelle = ' '.join(var_libelle.split())

            # Cliquer sur l'icône de recherche pour compter les occurrences
            search_icon = await var_element.query_selector('img[title*="Rechercher"]')
            if not search_icon:
                print(f"   {i}/{len(variables)}: {var_name} - ⚠️  Pas d'icône de recherche")
                variables_data.append({
                    'code': var_name,
                    'libelle': var_libelle,
                    'occurrences': 'N/A',
                    'documents': '',
                    'statut': 'Erreur'
                })
                continue

            await search_icon.scroll_into_view_if_needed()
            await search_icon.click()

            # Attendre que la popup apparaisse
            try:
                popup = await page.wait_for_selector('div:has-text("Emplacement(s) où est utilisée la variable")', timeout=3000)
            except:
                print(f"   {i}/{len(variables)}: {var_name} - ⚠️  Popup non trouvée")
                variables_data.append({
                    'code': var_name,
                    'libelle': var_libelle,
                    'occurrences': 'N/A',
                    'documents': '',
                    'statut': 'Erreur'
                })
                continue

            # Compter les occurrences et extraire les documents
            links = await popup.query_selector_all('a[onclick]')
            occurrence_count = len(links)

            # Extraire les noms de documents uniques
            documents = set()
            for link in links:
                text = await link.inner_text()
                text = text.replace('●', '').strip()
                # Prendre la partie avant le premier ' - '
                if ' - ' in text:
                    document_name = text.split(' - ')[0].strip()
                    documents.add(document_name)
                elif text:  # Si pas de ' - ', prendre tout le texte
                    documents.add(text)

            # Convertir en liste triée et joindre avec ', '
            documents_list = ', '.join(sorted(documents))

            # Déterminer le statut
            if occurrence_count == 0:
                statut = 'Non utilisée'
            else:
                statut = 'Utilisée'

            print(f"   {i}/{len(variables)}: {var_name} - {occurrence_count} occurrence(s) dans {len(documents)} document(s)")

            variables_data.append({
                'code': var_name,
                'libelle': var_libelle,
                'occurrences': occurrence_count,
                'documents': documents_list,
                'statut': statut
            })

            # Fermer la popup
            close_btn = await popup.query_selector('input[value="Fermer"]')
            if close_btn:
                await close_btn.click()
                await page.wait_for_timeout(300)

        except Exception as e:
            print(f"   {i}/{len(variables)}: Erreur - {str(e)}")
            variables_data.append({
                'code': 'Erreur',
                'libelle': '',
                'occurrences': 'N/A',
                'documents': '',
                'statut': f'Erreur: {str(e)}'
            })

    return variables_data


async def main():
    import argparse

    parser = argparse.ArgumentParser(description='Extraire les variables d\'un modèle Lexpol')
    parser.add_argument('--modele', type=str, help='Numéro du modèle Lexpol (optionnel)')
    parser.add_argument('--email', type=str, help='Email de connexion ou préfixe (ex: jeunesse ou redacteur.geda@jeunesse.gov.pf)')
    args = parser.parse_args()

    print("="*80)
    print("LEXPOL - EXTRACTION DES VARIABLES")
    print("="*80)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=config.HEADLESS, slow_mo=config.SLOW_MO)
        page = await browser.new_page(viewport={'width': 1800, 'height': 1000})

        # Connexion unifiée (gère tout : email, modèle, authentification)
        success = await LexpolConnection.connect_to_model(page, model_id=args.modele, email=args.email)
        if not success:
            await browser.close()
            return

        await LexpolConnection.ensure_variables_visible(page)

        # Extraire les variables
        variables_data = await extract_variables(page)

        # Générer le nom du fichier avec timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = f"lexpol_variables_{timestamp}.csv"

        # Sauvegarder dans un CSV
        with open(output_file, 'w', encoding='utf-8', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['code', 'libelle', 'occurrences', 'documents', 'statut'])
            writer.writeheader()
            writer.writerows(variables_data)

        # Statistiques
        total = len(variables_data)
        utilisees = sum(1 for v in variables_data if v['statut'] == 'Utilisée')
        non_utilisees = sum(1 for v in variables_data if v['statut'] == 'Non utilisée')
        erreurs = sum(1 for v in variables_data if v['statut'].startswith('Erreur'))

        print("\n" + "="*80)
        print("✅ EXTRACTION TERMINÉE")
        print("="*80)
        print(f"\n📊 Statistiques:")
        print(f"   Total de variables:     {total}")
        print(f"   Variables utilisées:    {utilisees}")
        print(f"   Variables non utilisées: {non_utilisees}")
        print(f"   Erreurs:                {erreurs}")
        print(f"\n💾 Fichier généré: {output_file}\n")

        await page.wait_for_timeout(2000)
        await browser.close()


if __name__ == "__main__":
    asyncio.run(main())
