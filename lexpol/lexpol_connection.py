#!/usr/bin/env python3
"""
Module de connexion à Lexpol
Gère l'authentification et l'initialisation du navigateur
"""
import lexpol_config as config


class LexpolConnection:
    """Gère la connexion et l'authentification à Lexpol"""

    @staticmethod
    async def setup_and_connect(page):
        """
        Configure la page et se connecte à Lexpol

        Args:
            page: Instance de page Playwright

        Returns:
            bool: True si la connexion a réussi
        """
        # Navigation vers l'URL
        print("🔑 Connexion...")
        await page.goto(config.LEXPOL_URL)
        await page.wait_for_load_state('networkidle')

        # Gérer la popup cookies AVANT la connexion
        print("🍪 Gestion popup cookies...")
        try:
            accept_btn = await page.wait_for_selector('button:has-text("Tout accepter")', timeout=3000)
            if accept_btn:
                await accept_btn.click()
                await page.wait_for_timeout(500)
                print("   ✅ Cookies acceptés")
        except:
            print("   ℹ️  Pas de popup cookies")

        # Vérifier si on doit se connecter
        if 'login' in page.url.lower():
            print("   Authentification requise...")
            await page.fill('input[name="email"]', config.EMAIL)
            await page.fill('input[name="motpasse"]', config.PASSWORD)
            await page.click('input[type="submit"]')
            await page.wait_for_load_state('networkidle')

            # Retourner au modèle
            await page.goto(config.LEXPOL_URL)
            await page.wait_for_load_state('networkidle')
        else:
            print("   Déjà authentifié")

        print("✅ Connecté")
        return True

    @staticmethod
    async def ensure_variables_visible(page):
        """
        S'assure que la section des variables est déployée

        Args:
            page: Instance de page Playwright
        """
        print("👁️  Déploiement section variables...")
        show_btn = await page.query_selector('#divVariablesAfficher')
        if show_btn and await show_btn.is_visible():
            await show_btn.click()
            await page.wait_for_timeout(1000)
