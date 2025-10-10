#!/usr/bin/env python3
"""
Outil de renommage de variables Lexpol utilisant l'architecture des stratégies
"""
import asyncio
import argparse
import csv
from playwright.async_api import async_playwright
import lexpol_config as config
from lexpol_connection import LexpolConnection
from lexpol_strategies import StrategyManager

async def open_all_documents(page):
    """Ouvre tous les documents pour accélérer les remplacements Summernote"""
    print("📂 Ouverture de tous les documents...")

    buttons = await page.query_selector_all('button[id^="bAffModifElement"]')
    print(f"   Trouvé {len(buttons)} document(s) à ouvrir")

    for i, btn in enumerate(buttons, 1):
        await btn.click()
        print(f"   ✅ Document {i}/{len(buttons)} ouvert")
        await page.wait_for_timeout(500)  # Petit délai entre chaque clic

    if len(buttons) > 0:
        await page.wait_for_timeout(3000)  # Attendre que tout soit chargé
        print("✅ Tous les documents sont ouverts\n")

async def process_variable(page, old_var, new_var, var_index=None, total_vars=None):
    """Traite le renommage d'une variable"""
    old_pattern = f"{{@{old_var}@}}"
    new_pattern = f"{{@{new_var}@}}"

    if var_index is not None and total_vars is not None:
        print(f"\n{'='*80}")
        print(f"🎯 Variable {var_index}/{total_vars}: {old_var} → {new_var}")
        print(f"{'='*80}")
    else:
        print(f"🎯 Traitement: {old_var} → {new_var}")

    # Trouver la variable
    print(f"🔍 Recherche de {old_var}...")
    variables = await page.query_selector_all('li[id^="variable"]')

    variable_element = None
    for var in variables:
        var_code = await var.query_selector('.variableCodeLibelle')
        if var_code:
            code_text = await var_code.inner_text()
            if old_var in code_text:
                print(f"✅ Variable trouvée: {code_text}")
                variable_element = var
                break

    if not variable_element:
        print(f"❌ Variable non trouvée: {old_var}")
        print(f"   Nombre de variables trouvées: {len(variables)}")
        if variables:
            print("   Premières variables:")
            for v in variables[:10]:
                var_code = await v.query_selector('.variableCodeLibelle')
                if var_code:
                    text = await var_code.inner_text()
                    print(f"     - {text}")
        return False

    # Cliquer sur l'icône de recherche pour ouvrir la popup des occurrences
    search_icon = await variable_element.query_selector('img[title*="Rechercher"]')
    if not search_icon:
        print("❌ Icône de recherche non trouvée")
        return False

    await search_icon.scroll_into_view_if_needed()
    await search_icon.click()
    await page.wait_for_timeout(2000)

    # Lister les occurrences
    print(f"📊 Liste des occurrences...")
    popup = await page.query_selector('div:has-text("Emplacement(s) où est utilisée la variable")')
    if not popup:
        print("❌ Popup non trouvée")
        return False

    links = await popup.query_selector_all('a[onclick]')
    print(f"   Trouvé {len(links)} liens au total")

    # Collecter toutes les occurrences
    occurrences = []
    for link in links:
        text = await link.inner_text()
        text = text.replace('●', '').strip()
        onclick = await link.get_attribute('onclick')
        occurrences.append({'text': text, 'onclick': onclick})

    if not occurrences:
        print("❌ Aucune occurrence trouvée")
        return False

    # Initialiser le gestionnaire de stratégies
    strategy_manager = StrategyManager()

    # Compter les occurrences traitables
    processable_count = 0
    for occ in occurrences:
        strategy = await strategy_manager.get_strategy(occ['text'])
        if strategy:
            processable_count += 1
            print(f"   ✅ {occ['text']}")
        else:
            print(f"   ⏭️  IGNORÉ: {occ['text']}")

    if processable_count == 0:
        print("❌ Aucune occurrence traitable")
        return False

    print(f"\n🎯 Traitement de {processable_count} occurrence(s)")
    initial_count = processable_count

    # Fermer la popup
    close_btn = await popup.query_selector('input[value="Fermer"]')
    if close_btn:
        await close_btn.click()
        await page.wait_for_timeout(500)

    # Traiter chaque occurrence via le gestionnaire de stratégies
    success_count = 0
    for i, occ in enumerate(occurrences, 1):
        # Vérifier si une stratégie peut traiter cette occurrence
        strategy = await strategy_manager.get_strategy(occ['text'])
        if not strategy:
            continue

        print(f"\n--- Occurrence {i}/{len(occurrences)} ---")

        # Utiliser la stratégie appropriée
        success = await strategy_manager.process_occurrence(page, occ, old_pattern, new_pattern)

        if success:
            success_count += 1
            # Pas besoin de recharger la page, on passe directement à l'occurrence suivante

    print("\n✅ Terminé!")

    # Relancer la recherche pour vérifier combien de remplacements ont eu lieu
    print("\n🔍 Vérification finale...")
    await page.goto(config.LEXPOL_URL)
    await page.wait_for_load_state('networkidle')
    await LexpolConnection.ensure_variables_visible(page)

    # Retrouver la variable
    variables = await page.query_selector_all('li[id^="variable"]')
    variable_element = None
    for var in variables:
        var_code = await var.query_selector('.variableCodeLibelle')
        if var_code:
            code_text = await var_code.inner_text()
            if old_var in code_text:
                variable_element = var
                break

    if variable_element:
        # Cliquer sur l'icône de recherche
        search_icon = await variable_element.query_selector('img[title*="Rechercher"]')
        if search_icon:
            await search_icon.scroll_into_view_if_needed()
            await search_icon.click()
            await page.wait_for_timeout(2000)

            # Compter les occurrences traitables restantes
            popup = await page.query_selector('div:has-text("Emplacement(s) où est utilisée la variable")')
            if popup:
                links = await popup.query_selector_all('a[onclick]')
                remaining_processable = 0
                for link in links:
                    text = await link.inner_text()
                    text = text.replace('●', '').strip()
                    # Vérifier si cette occurrence est traitable
                    if await strategy_manager.get_strategy(text):
                        remaining_processable += 1

                replaced_count = initial_count - remaining_processable
                print(f"\n📊 RÉSULTAT:")
                print(f"   Occurrences initiales traitables: {initial_count}")
                print(f"   Occurrences restantes traitables: {remaining_processable}")
                print(f"   ✅ Remplacements réussis: {replaced_count}")
                print(f"   (Succès attendus: {success_count})")

                # Si toutes les occurrences ont été traitées, renommer la variable elle-même
                if remaining_processable == 0:
                    print(f"\n🎉 Toutes les occurrences traitées ! Renommage de la variable...")

                    # Fermer la popup
                    close_btn = await popup.query_selector('input[value="Fermer"]')
                    if close_btn:
                        await close_btn.click()
                        await page.wait_for_timeout(500)

                    # Retrouver la variable dans la liste (span avec classe variableCodeLibelle)
                    var_code_spans = await page.query_selector_all('span.variableCodeLibelle')
                    for span in var_code_spans:
                        code_text = await span.inner_text()
                        if old_var in code_text:
                            print(f"   🔍 Variable trouvée: {code_text}")

                            # Double-cliquer sur le span pour activer l'édition
                            print(f"   👆 Double-clic pour activer l'édition...")
                            await span.scroll_into_view_if_needed()
                            await span.dblclick()
                            await page.wait_for_timeout(500)

                            # Trouver le champ input qui est apparu (dans le span variableCodeEdit)
                            # Le input est de type class="data_form"
                            code_input = await page.evaluate(f'''() => {{
                                const spans = Array.from(document.querySelectorAll('span[id^="variableCodeEdit"]'));
                                for (const span of spans) {{
                                    if (span.style.display !== 'none') {{
                                        const input = span.querySelector('input.data_form');
                                        if (input) return input.id || 'found';
                                    }}
                                }}
                                return null;
                            }}''')

                            if code_input:
                                print(f"   ✏️  Modification du code de la variable...")

                                # Trouver l'input et le modifier
                                if code_input == 'found':
                                    # Pas d'ID, utiliser JavaScript
                                    await page.evaluate(f'''() => {{
                                        const spans = Array.from(document.querySelectorAll('span[id^="variableCodeEdit"]'));
                                        for (const span of spans) {{
                                            if (span.style.display !== 'none') {{
                                                const input = span.querySelector('input.data_form');
                                                if (input) {{
                                                    input.value = '{new_var}';
                                                    // Simuler Enter pour valider
                                                    const event = new KeyboardEvent('keyup', {{ key: 'Enter', keyCode: 13, which: 13 }});
                                                    span.dispatchEvent(event);
                                                    return true;
                                                }}
                                            }}
                                        }}
                                        return false;
                                    }}''')
                                else:
                                    # Utiliser l'ID
                                    input_elem = await page.query_selector(f'#{code_input}')
                                    if input_elem:
                                        await input_elem.fill(new_var)
                                        await input_elem.press('Enter')

                                await page.wait_for_timeout(2000)
                                print(f"   ✅ Variable renommée: {old_var} → {new_var}")
                                return True
                            else:
                                print(f"   ❌ Champ de saisie non trouvé après double-clic")
                            break
                else:
                    print(f"\n⚠️  {remaining_processable} occurrence(s) restante(s) - variable NON renommée")
                    print(f"   Corrigez les erreurs et relancez le script")
                    return False

    return False

async def main():
    parser = argparse.ArgumentParser(description='Renommer des variables dans Lexpol')
    parser.add_argument('--all', action='store_true', help='Traiter toutes les variables du CSV')
    args = parser.parse_args()

    # Lire le CSV
    with open(config.CSV_FILE, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        mappings = list(reader)

    if not mappings:
        print("❌ Aucun renommage dans le CSV")
        return

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False, slow_mo=500)
        page = await browser.new_page(viewport={'width': 1800, 'height': 1000})

        # Connexion via la classe LexpolConnection
        await LexpolConnection.setup_and_connect(page)
        await LexpolConnection.ensure_variables_visible(page)

        # Ouvrir tous les documents pour optimiser les traitements Summernote
        await open_all_documents(page)

        if args.all:
            # Traiter toutes les variables
            print(f"🚀 Mode --all: Traitement de {len(mappings)} variable(s)")
            success_count = 0

            for i, mapping in enumerate(mappings, 1):
                old_var = mapping['old_variable']
                new_var = mapping['new_variable']

                success = await process_variable(page, old_var, new_var, i, len(mappings))

                if success:
                    success_count += 1

                # Attendre un peu entre chaque variable
                if i < len(mappings):
                    await page.wait_for_timeout(2000)

            print(f"\n{'='*80}")
            print(f"🎉 TRAITEMENT TERMINÉ")
            print(f"   Variables traitées avec succès: {success_count}/{len(mappings)}")
            print(f"{'='*80}")
        else:
            # Traiter uniquement la première variable (comportement par défaut)
            old_var = mappings[0]['old_variable']
            new_var = mappings[0]['new_variable']
            await process_variable(page, old_var, new_var)

        await page.wait_for_timeout(5000)
        await browser.close()

if __name__ == "__main__":
    asyncio.run(main())
