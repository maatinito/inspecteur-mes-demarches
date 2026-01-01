#!/usr/bin/env python3
"""
Script de tri des variables d'un modèle Lexpol
Trie les variables par ordre alphabétique en respectant la casse mais en ignorant les accents
Exemple: "à la présidente" sera trié avec "a", "É" avec "E"
"""
import asyncio
import argparse
import re
import unicodedata
from playwright.async_api import async_playwright
import lexpol_config as config
from lexpol_connection import LexpolConnection


def remove_accents(text):
    """
    Retire les accents d'une chaîne pour la comparaison alphabétique
    Exemple: "à" → "a", "É" → "E"
    """
    # Normaliser en NFD (décompose les caractères accentués en caractère + accent)
    nfd = unicodedata.normalize('NFD', text)
    # Filtrer les caractères de combinaison (Mn = Mark, nonspacing = accents)
    return ''.join(char for char in nfd if unicodedata.category(char) != 'Mn')


async def get_all_variables(page):
    """
    Récupère toutes les variables avec leurs informations
    Filtre les variables virtuelles (_en_lettres) qui sont générées automatiquement

    Returns:
        list: Liste de dictionnaires {code, id_variable, position}
    """
    variables = await page.evaluate('''() => {
        const vars = [];
        const varElements = document.querySelectorAll('li[id^="variable"]');

        varElements.forEach((elem) => {
            const codeElem = elem.querySelector('.variableCodeLibelle');
            if (codeElem) {
                const code = codeElem.innerText.replace(/{@|@}/g, '').trim();

                // Filtrer les variables virtuelles (_en_lettres)
                if (code.endsWith('_en_lettres')) {
                    return;  // Skip cette variable virtuelle
                }

                const id_variable = elem.id.replace('variable', '');

                // Utiliser la position dans le DOM réel
                const position = Array.from(varElements).indexOf(elem);

                vars.push({
                    code,
                    id_variable,
                    position
                });
            }
        });

        return vars;
    }''')

    return variables


async def get_all_variables_with_retry(page, max_retries=3, expected_min_count=1):
    """
    Récupère les variables avec retry en cas de liste vide

    Args:
        page: Instance de page Playwright
        max_retries: Nombre maximum de tentatives
        expected_min_count: Nombre minimum de variables attendues

    Returns:
        list: Liste de variables ou None en cas d'échec
    """
    for attempt in range(max_retries):
        variables = await get_all_variables(page)

        if len(variables) >= expected_min_count:
            return variables

        if attempt < max_retries - 1:
            # Attendre un peu plus avant de réessayer
            await page.wait_for_timeout(1500)

    # Dernière tentative sans vérification
    return await get_all_variables(page)


async def get_model_id(page):
    """
    Extrait l'ID du modèle (idw) depuis l'URL de la page

    Returns:
        str: ID du modèle
    """
    url = page.url
    match = re.search(r'idw=(\d+)', url)
    if match:
        return match.group(1)
    return None


async def move_variable(page, idw, id_variable, direction, count=1):
    """
    Déplace une variable de N positions

    Args:
        page: Instance de page Playwright
        idw: ID du modèle
        id_variable: ID de la variable à déplacer
        direction: -1 pour monter, 1 pour descendre
        count: Nombre de positions à déplacer (optimisation: déplace de N positions en un appel)
    """
    # Calculer le sens total (direction * count)
    sens = direction * count
    await page.evaluate(f'variable_deplacer({idw}, {id_variable}, {sens})')

    # Attendre que le DOM soit mis à jour en vérifiant que la variable a bien bougé
    await page.wait_for_timeout(1000)  # Augmenté de 500ms à 1000ms

    # Attendre que l'état "networkidle" soit atteint (AJAX terminé)
    try:
        await page.wait_for_load_state('networkidle', timeout=5000)  # Augmenté de 3s à 5s
    except:
        pass  # Si timeout, on continue quand même


async def sort_variables(page, idw, dry_run=False, reverse=False):
    """
    Trie les variables par ordre alphabétique (respecte la casse)

    Args:
        page: Instance de page Playwright
        idw: ID du modèle
        dry_run: Si True, affiche seulement ce qui serait fait sans l'exécuter
        reverse: Si True, trie en ordre inverse (Z-A)
    """
    print("\n" + "="*80)
    print("📋 TRI DES VARIABLES")
    print("="*80 + "\n")

    # Récupérer les variables avec retry
    variables = await get_all_variables_with_retry(page, max_retries=3, expected_min_count=1)
    print(f"📊 Trouvé {len(variables)} variable(s)\n")

    if not variables:
        print("❌ Aucune variable trouvée")
        return

    # Afficher l'ordre actuel
    print("📌 Ordre actuel:")
    for i, var in enumerate(variables):
        print(f"   {i+1}. {var['code']}")

    # Calculer l'ordre cible (tri alphabétique respectant la casse, ignorant les accents)
    sorted_variables = sorted(variables, key=lambda x: remove_accents(x['code']), reverse=reverse)

    print("\n🎯 Ordre cible:")
    for i, var in enumerate(sorted_variables):
        print(f"   {i+1}. {var['code']}")

    # Vérifier si un tri est nécessaire
    if variables == sorted_variables:
        print("\n✅ Les variables sont déjà triées !")
        return

    if dry_run:
        print("\n⚠️  Mode DRY RUN - Aucune modification ne sera appliquée")
        print("\n📝 Déplacements qui seraient effectués:")
    else:
        print("\n🔄 Application du tri...")

    # Algorithme de tri par sélection
    # Pour chaque position cible, on place la bonne variable
    total_moves = 0
    expected_var_count = len(sorted_variables)

    for target_position in range(len(sorted_variables)):
        # ✅ IMPORTANT: Récupérer la liste ACTUELLE à chaque itération avec retry
        current_vars = await get_all_variables_with_retry(page, max_retries=3, expected_min_count=expected_var_count)

        # Vérifier que nous avons bien récupéré les variables
        if not current_vars or len(current_vars) == 0:
            print(f"   ⚠️  Erreur: impossible de récupérer les variables (liste vide)")
            print(f"   ℹ️  Attente de 3 secondes avant nouvelle tentative...")
            await page.wait_for_timeout(3000)
            current_vars = await get_all_variables_with_retry(page, max_retries=5, expected_min_count=1)

            if not current_vars:
                print(f"   ❌ Abandon: impossible de récupérer les variables après plusieurs tentatives")
                break

        # ✅ Re-calculer l'ordre trié basé sur la liste actuelle (ignorant les accents)
        current_sorted = sorted(current_vars, key=lambda x: remove_accents(x['code']), reverse=reverse)

        # Vérifier qu'on n'a pas dépassé le nombre de variables actuelles
        if target_position >= len(current_sorted):
            print(f"   ℹ️  Tri terminé (position {target_position} >= {len(current_sorted)} variables)")
            break

        # ✅ La variable qui devrait être à target_position dans l'ordre trié
        target_var = current_sorted[target_position]

        # Trouver la position actuelle de cette variable dans la liste NON triée
        current_position = None
        for i, var in enumerate(current_vars):
            if var['id_variable'] == target_var['id_variable']:
                current_position = i
                break

        if current_position is None:
            print(f"   ❌ Variable {target_var['code']} non trouvée")
            continue

        # Calculer le nombre de déplacements nécessaires
        moves_needed = current_position - target_position

        if moves_needed == 0:
            # Déjà à la bonne position
            continue

        if moves_needed > 0:
            # Doit monter
            direction = -1
            direction_text = "↑"
        else:
            # Doit descendre
            direction = 1
            direction_text = "↓"
            moves_needed = abs(moves_needed)

        print(f"   {direction_text} {target_var['code']}: position {current_position} → {target_position} ({moves_needed} déplacement(s))")

        if not dry_run:
            # Appliquer le déplacement en une seule fois (optimisation)
            await move_variable(page, idw, target_var['id_variable'], direction, count=moves_needed)
            # Forcer une relecture pour garantir que le DOM est complètement stabilisé
            _ = await get_all_variables_with_retry(page, max_retries=3, expected_min_count=expected_var_count)
            total_moves += moves_needed

    if not dry_run:
        # Vérification finale
        print("\n🔍 Vérification finale...")
        final_vars = await get_all_variables_with_retry(page, max_retries=5, expected_min_count=expected_var_count)

        print("\n📌 Ordre final:")
        for i, var in enumerate(final_vars):
            print(f"   {i+1}. {var['code']}")

        # Vérifier que le tri est correct (en ignorant les accents)
        if reverse:
            is_sorted = all(remove_accents(final_vars[i]['code']) >= remove_accents(final_vars[i+1]['code'])
                           for i in range(len(final_vars)-1))
        else:
            is_sorted = all(remove_accents(final_vars[i]['code']) <= remove_accents(final_vars[i+1]['code'])
                           for i in range(len(final_vars)-1))

        if is_sorted:
            print(f"\n✅ TRI TERMINÉ - {total_moves} déplacement(s) effectué(s)")
        else:
            print(f"\n⚠️  TRI INCOMPLET - Vérifiez manuellement")
    else:
        print("\n✅ SIMULATION TERMINÉE")


async def main():
    parser = argparse.ArgumentParser(description='Trier les variables d\'un modèle Lexpol')
    parser.add_argument('--modele', type=str, help='Numéro du modèle Lexpol (optionnel)')
    parser.add_argument('--email', type=str, help='Email de connexion ou préfixe (ex: jeunesse ou redacteur.geda@jeunesse.gov.pf)')
    parser.add_argument('--dry-run', action='store_true', help='Simulation sans effectuer les modifications')
    parser.add_argument('--reverse', action='store_true', help='Trier en ordre inverse (Z-A)')
    parser.add_argument('--browser', type=str, default='firefox', choices=['firefox', 'chromium'],
                        help='Navigateur à utiliser (firefox par défaut car il affiche l\'ordre réel du serveur, chromium applique un tri JS automatique)')
    parser.add_argument('--debug-no-js', action='store_true',
                        help='DEBUG: Désactiver JavaScript pour voir l\'ordre HTML brut du serveur')
    args = parser.parse_args()

    print("="*80)
    print("LEXPOL - TRI DES VARIABLES")
    print("="*80)

    async with async_playwright() as p:
        # Firefox affiche l'ordre réel du serveur, Chromium applique un tri automatique JavaScript
        if args.browser == 'firefox':
            print("🦊 Utilisation de Firefox (affiche l'ordre réel du serveur)")
            browser = await p.firefox.launch(headless=config.HEADLESS, slow_mo=config.SLOW_MO)
        else:
            print("🔷 Utilisation de Chromium (ATTENTION: Lexpol applique un tri automatique JS)")
            browser = await p.chromium.launch(headless=config.HEADLESS, slow_mo=config.SLOW_MO)

        # Créer le contexte avec ou sans JavaScript
        if args.debug_no_js:
            print("⚠️  DEBUG: JavaScript DÉSACTIVÉ - Vous verrez l'ordre HTML brut mais ne pourrez pas trier")
            context = await browser.new_context(
                viewport={'width': 1800, 'height': 1000},
                java_script_enabled=False
            )
            page = await context.new_page()
        else:
            page = await browser.new_page(viewport={'width': 1800, 'height': 1000})

        # Connexion unifiée (gère tout : email, modèle, authentification)
        success = await LexpolConnection.connect_to_model(page, model_id=args.modele, email=args.email)
        if not success:
            await browser.close()
            return

        await LexpolConnection.ensure_variables_visible(page)

        # Extraire l'ID du modèle
        idw = await get_model_id(page)
        if not idw:
            print("❌ Impossible d'extraire l'ID du modèle")
            await browser.close()
            return

        print(f"🔑 ID du modèle: {idw}")

        # Trier les variables
        await sort_variables(page, idw, dry_run=args.dry_run, reverse=args.reverse)

        await page.wait_for_timeout(3000)
        await browser.close()


if __name__ == "__main__":
    asyncio.run(main())
