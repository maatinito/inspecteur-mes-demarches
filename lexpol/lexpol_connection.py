#!/usr/bin/env python3
"""
Module de connexion à Lexpol
Gère l'authentification et l'initialisation du navigateur
"""
import lexpol_config as config


class LexpolConnection:
    """Gère la connexion et l'authentification à Lexpol"""

    @staticmethod
    async def get_model_url(page, model_id, email=None, password=None):
        """
        Récupère l'URL complète d'un modèle à partir de son ID

        Args:
            page: Instance de page Playwright
            model_id: Numéro du modèle (ex: 620292)
            email: Email de connexion (optionnel)
            password: Mot de passe (optionnel)

        Returns:
            str: URL complète du modèle avec le hash hk, ou None si non trouvé
        """
        target_email = email or config.EMAIL
        target_password = password or config.PASSWORD

        print(f"🔍 Recherche du modèle {model_id}...")

        # Aller sur la page de liste des modèles
        list_url = "https://lexpol.cloud.pf/extranet/geda_dossiers_modele.php"
        await page.goto(list_url)
        await page.wait_for_load_state('networkidle')

        # Gérer les cookies si nécessaire
        try:
            accept_btn = await page.wait_for_selector('button:has-text("Tout accepter")', timeout=2000)
            if accept_btn:
                await accept_btn.click()
                await page.wait_for_timeout(500)
        except:
            pass

        # Vérifier si on doit se connecter
        if 'login' in page.url.lower():
            print("   Authentification requise...")
            await page.fill('input[name="email"]', target_email)
            await page.fill('input[name="motpasse"]', target_password)
            await page.click('input[type="submit"]')
            await page.wait_for_load_state('networkidle')

            # Retourner à la page de liste
            await page.goto(list_url)
            await page.wait_for_load_state('networkidle')

        # Chercher le lien du modèle
        link_selector = f'a[id="libModele{model_id}"]'
        link = await page.query_selector(link_selector)

        if not link:
            print(f"   ❌ Modèle {model_id} non trouvé dans la liste")
            return None

        # Récupérer l'attribut href
        href = await link.get_attribute('href')
        if not href:
            print(f"   ❌ Lien du modèle {model_id} invalide")
            return None

        # Construire l'URL complète
        if href.startswith('http'):
            model_url = href
        else:
            # href relatif (ex: geda_dossier.php?idw=620292&hk=...)
            model_url = f"https://lexpol.cloud.pf/extranet/{href}"

        # Récupérer le nom du modèle pour affichage
        model_name = await link.inner_text()
        print(f"   ✅ Modèle trouvé: {model_name}")
        print(f"   🔗 URL: {model_url}")

        return model_url

    @staticmethod
    async def setup_and_connect(page, url=None, email=None, password=None):
        """
        Configure la page et se connecte à Lexpol

        Args:
            page: Instance de page Playwright
            url: URL du modèle (optionnel, utilise config.LEXPOL_URL par défaut)
            email: Email de connexion (optionnel, utilise config.EMAIL par défaut)
            password: Mot de passe (optionnel, utilise config.PASSWORD par défaut)

        Returns:
            bool: True si la connexion a réussi
        """
        # Utiliser les valeurs de config si non fournies
        target_url = url or config.LEXPOL_URL
        target_email = email or config.EMAIL
        target_password = password or config.PASSWORD

        # Navigation vers l'URL
        print("🔑 Connexion...")
        await page.goto(target_url)
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
            await page.fill('input[name="email"]', target_email)
            await page.fill('input[name="motpasse"]', target_password)
            await page.click('input[type="submit"]')
            await page.wait_for_load_state('networkidle')

            # Retourner au modèle
            await page.goto(target_url)
            await page.wait_for_load_state('networkidle')
        else:
            print("   Déjà authentifié")

        print("✅ Connecté")
        return True

    @staticmethod
    async def connect_to_model(page, model_id=None, email=None, password=None):
        """
        Fonction unifiée pour se connecter à un modèle Lexpol
        Gère automatiquement :
        - Construction de l'email depuis un préfixe
        - Récupération de l'URL du modèle si model_id est fourni
        - Connexion et authentification

        Args:
            page: Instance de page Playwright
            model_id: Numéro du modèle (optionnel, utilise config par défaut)
            email: Email complet ou préfixe (optionnel, utilise config par défaut)
            password: Mot de passe (optionnel, utilise config par défaut)

        Returns:
            bool: True si la connexion a réussi
        """
        # Construire l'email si c'est un préfixe
        target_email = email
        if email and '@' not in email:
            target_email = f"redacteur.geda@{email}.gov.pf"
            print(f"📧 Utilisation de l'email: {target_email}")
        elif email:
            print(f"📧 Utilisation de l'email: {email}")

        # Récupérer l'URL du modèle si model_id est fourni
        url = None
        if model_id:
            url = await LexpolConnection.get_model_url(page, model_id, email=target_email, password=password)
            if not url:
                print(f"❌ Impossible de trouver le modèle {model_id}")
                return False

        # Se connecter
        return await LexpolConnection.setup_and_connect(page, url=url, email=target_email, password=password)

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
