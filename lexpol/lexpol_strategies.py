#!/usr/bin/env python3
"""
Stratégies de remplacement pour différents types d'éléments Lexpol
"""
from abc import ABC, abstractmethod
import re
import json


def create_textarea_search_js(container_id: str, old_pattern_search: str, old_pattern_lettres_search: str, textarea_selector: str = 'textarea') -> str:
    """
    Génère le code JavaScript pour rechercher un textarea dans un conteneur

    Args:
        container_id: ID du conteneur (param1)
        old_pattern_search: Pattern de recherche normal (ex: {@variable@)
        old_pattern_lettres_search: Pattern de recherche _en_lettres (ex: {@variable_en_lettres@)
        textarea_selector: Sélecteur CSS pour les textareas (ex: 'textarea', 'textarea.editeur', 'textarea.editeursimple')

    Returns:
        Code JavaScript à exécuter via page.evaluate()
    """
    return f'''() => {{
        // Chercher d'abord dans le conteneur spécifique
        const container = document.getElementById('{container_id}');
        if (!container) {{
            console.log('Container not found: {container_id}');
            // Fallback: chercher globalement
            const textareas = Array.from(document.querySelectorAll('{textarea_selector}'));
            for (const ta of textareas) {{
                if (ta.value && (ta.value.includes('{old_pattern_search}') || ta.value.includes('{old_pattern_lettres_search}'))) {{
                    return ta.id;
                }}
            }}
            return null;
        }}

        // Chercher uniquement les textareas DANS ce conteneur
        const textareas = Array.from(container.querySelectorAll('{textarea_selector}'));
        for (const ta of textareas) {{
            if (ta.value && (ta.value.includes('{old_pattern_search}') || ta.value.includes('{old_pattern_lettres_search}'))) {{
                return ta.id;
            }}
        }}
        return null;
    }}'''


def replace_variable_with_suffixes(text: str, old_var: str, new_var: str) -> tuple[str, int]:
    """
    Remplace une variable Lexpol en préservant les suffixes éventuels

    Formats supportés:
    - {@variable@} → {@nouvelle_variable@}
    - {@variable@:suffixe} → {@nouvelle_variable@:suffixe}
    - {@variable_en_lettres@} → {@nouvelle_variable_en_lettres@}
    - {@variable_en_lettres@:suffixe} → {@nouvelle_variable_en_lettres@:suffixe}

    Formats booléens supportés:
    - {@SI_variable@} → {@SI_nouvelle_variable@}
    - {@/SI_variable@} → {@/SI_nouvelle_variable@}
    - {@SI_NON_variable@} → {@SI_NON_nouvelle_variable@}
    - {@/SI_NON_variable@} → {@/SI_NON_nouvelle_variable@}
    Et leurs variantes _en_lettres

    Args:
        text: Texte contenant les variables
        old_var: Nom de l'ancienne variable (ex: "association.nom")
        new_var: Nom de la nouvelle variable (ex: "Association - Nom")

    Returns:
        tuple: (texte modifié, nombre de remplacements effectués)
    """
    new_text = text
    total_count = 0

    # Échapper la variable pour regex
    old_var_escaped = re.escape(old_var)

    # Liste des patterns à remplacer
    patterns = [
        # Patterns simples
        (r'\{@' + old_var_escaped + r'@([^}]*)\}', r'{@' + new_var + r'@\1}'),
        (r'\{@' + old_var_escaped + r'_en_lettres@([^}]*)\}', r'{@' + new_var + r'_en_lettres@\1}'),

        # Patterns booléens SI (pas de _en_lettres pour les booléens)
        (r'\{@SI_' + old_var_escaped + r'@([^}]*)\}', r'{@SI_' + new_var + r'@\1}'),
        (r'\{@/SI_' + old_var_escaped + r'@([^}]*)\}', r'{@/SI_' + new_var + r'@\1}'),

        # Patterns booléens SI_NON
        (r'\{@SI_NON_' + old_var_escaped + r'@([^}]*)\}', r'{@SI_NON_' + new_var + r'@\1}'),
        (r'\{@/SI_NON_' + old_var_escaped + r'@([^}]*)\}', r'{@/SI_NON_' + new_var + r'@\1}'),
    ]

    # Appliquer tous les patterns
    for pattern_str, replacement_str in patterns:
        pattern = re.compile(pattern_str)
        new_text, count = pattern.subn(replacement_str, new_text)
        total_count += count

    return new_text, total_count


async def wait_for_element_ready(page, selector: str, timeout: int = 5000) -> bool:
    """
    Attend qu'un élément soit présent ET visible dans le DOM (optimisation des timeouts)

    Args:
        page: Instance de page Playwright
        selector: Sélecteur CSS de l'élément
        timeout: Timeout maximum en ms (défaut 5s)

    Returns:
        bool: True si l'élément est prêt, False sinon
    """
    try:
        await page.wait_for_selector(selector, state='visible', timeout=timeout)
        return True
    except:
        return False


async def fill_textarea_with_clear(textarea_element, new_value: str):
    """
    Remplit un textarea en utilisant le pattern Ctrl+A + Backspace + fill()
    Ce pattern garantit que le contenu est correctement remplacé même si le focus n'est pas optimal

    Args:
        textarea_element: ElementHandle du textarea
        new_value: Nouvelle valeur à insérer
    """
    await textarea_element.press('Control+A')
    await textarea_element.press('Backspace')
    await textarea_element.fill(new_value, force=True)


class ReplacementStrategy(ABC):
    """Classe abstraite pour les stratégies de remplacement"""

    @abstractmethod
    async def can_handle(self, occurrence_text: str) -> bool:
        """
        Détermine si cette stratégie peut traiter l'occurrence

        Args:
            occurrence_text: Texte de l'occurrence (ex: "Rapport - N5 - Référence(s)")

        Returns:
            bool: True si cette stratégie peut traiter l'occurrence
        """
        pass

    @abstractmethod
    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence et effectue le remplacement

        Args:
            page: Instance de page Playwright
            occurrence: Dict avec 'text' et 'onclick'
            old_pattern: Pattern à remplacer (ex: {@demande.dateDemande@})
            new_pattern: Nouveau pattern (ex: {@Dossier déposé le@})

        Returns:
            bool: True si le remplacement a réussi
        """
        pass


class SquareEditStrategy(ReplacementStrategy):
    """
    Stratégie pour les éléments de type Référence(s) utilisant square_edit.png

    PHILOSOPHIE:
    - Interface Lexpol: Simple textarea désactivé par défaut (readonly)
    - Activation: Clic sur icône square_edit.png pour activer l'édition
    - Édition: Le textarea devient éditable, l'utilisateur peut modifier
    - Sauvegarde: Re-clic sur square_edit.png pour sauvegarder et verrouiller

    IMPLÉMENTATION:
    - Trouve le textarea par son contenu (contient la variable)
    - Récupère l'onclick de l'icône square_edit associée
    - Exécute onclick pour OUVRIR l'éditeur
    - Remplace le contenu avec pattern Ctrl+A + Backspace + fill()
    - Exécute onclick pour FERMER et sauvegarder

    UTILISÉ POUR: Référence(s) des éléments
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les Référence(s) et Attendus (Vu) utilisant square_edit.png"""
        import re

        # Traiter les Référence(s) ET les Attendus (Vu) avec square_edit.png
        return bool(re.search(r'(Référence\(s\)|Attendus \(Vu\))( n° \d+)?', occurrence_text))

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence de type Référence(s) avec square_edit

        Process:
        1. Exécute goVariable() pour afficher la section
        2. Trouve le textarea contenant le pattern
        3. Trouve l'icône square_edit.png associée
        4. Ouvre l'éditeur (clic sur square_edit)
        5. Sélectionne tout le texte (Ctrl+A)
        6. Supprime (Backspace)
        7. Remplit avec la nouvelle valeur (remplace pattern ET pattern_en_lettres)
        8. Enregistre (clic sur square_edit)
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Exécuter goVariable()
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")
        await page.wait_for_timeout(3000)

        # DOUBLE REMPLACEMENT: pattern ET pattern_en_lettres
        # Extraire la variable de old_pattern: {@variable@} -> variable
        var_match = re.search(r'{@([^@]+)@}', old_pattern)
        if not var_match:
            print(f"   ❌ Pattern invalide: {old_pattern}")
            return False

        old_var = var_match.group(1)
        new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
        if not new_var_match:
            print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
            return False
        new_var = new_var_match.group(1)

        # APPROCHE GÉNÉRIQUE basée sur la structure DOM
        # 1. Trouver le <p> de prévisualisation (param1)
        # 2. Remonter au <tr> parent
        # 3. Chercher le premier <textarea> dans ce <tr>
        # 4. Chercher le bouton square_edit dans ce <tr>
        print(f"   🔍 Recherche du textarea et square_edit via structure DOM...")

        dom_info = await page.evaluate(f'''() => {{
            // 1. Trouver le <p> de prévisualisation
            const preview_p = document.getElementById('{param1}');
            if (!preview_p) return {{ error: 'Prévisualisation non trouvée' }};

            // 2. Remonter au <tr> parent
            const tr = preview_p.closest('tr');
            if (!tr) return {{ error: 'TR parent non trouvé' }};

            // 3. Chercher le premier <textarea> dans ce <tr>
            const textarea = tr.querySelector('textarea');
            if (!textarea) return {{ error: 'Aucun textarea dans le TR' }};

            // 4. Chercher le bouton square_edit dans ce <tr>
            const img = tr.querySelector('img[src*="square_edit.png"]');
            if (!img) return {{ error: 'Bouton square_edit non trouvé' }};
            const link = img.closest('a');
            if (!link) return {{ error: 'Lien square_edit non trouvé' }};

            // Retourner les infos
            return {{
                success: true,
                textarea_id: textarea.id,
                textarea_value: textarea.value,
                edit_onclick: link.getAttribute('onclick')
            }};
        }}''')

        if 'error' in dom_info:
            print(f"   ❌ {dom_info['error']}")
            return False

        textarea_id = dom_info['textarea_id']
        edit_onclick = dom_info['edit_onclick']

        print(f"   ✅ Textarea: #{textarea_id}")
        print(f"   ✅ square_edit onclick: {edit_onclick[:80]}...")
        print(f"   🐛 DEBUG - Valeur AVANT remplacement (longueur: {len(dom_info['textarea_value'])}):")
        print(f"      {dom_info['textarea_value'][:300]}...")

        # Récupérer le textarea ElementHandle
        textarea = await page.query_selector(f'textarea[id="{textarea_id}"]')
        if not textarea:
            print(f"   ❌ Textarea inaccessible")
            return False

        # Utiliser la valeur déjà récupérée
        old_value = dom_info['textarea_value']

        # Appliquer les remplacements en préservant les suffixes
        new_value, total_count = replace_variable_with_suffixes(old_value, old_var, new_var)

        if total_count == 0:
            print(f"   ⚠️  Aucun remplacement nécessaire (patterns non trouvés)")
            return False

        print(f"   🔄 {total_count} remplacement(s) effectué(s)")
        print(f"   🐛 DEBUG - Valeur APRÈS remplacement (longueur: {len(new_value)}):")
        print(f"      {new_value[:300]}...")

        # OUVRIR l'éditeur
        print(f"   👆 OUVRIR l'éditeur (clic sur square_edit)...")
        await page.evaluate(edit_onclick)
        await page.wait_for_timeout(500)

        # Vider et remplir le textarea avec le pattern standard
        await fill_textarea_with_clear(textarea, new_value)
        print(f"   ✅ Contenu remplacé")

        # ENREGISTRER
        print(f"   💾 ENREGISTRER...")
        await page.wait_for_timeout(2000)  # Attendre avant de cliquer
        await page.evaluate(edit_onclick)
        await page.wait_for_timeout(3000)  # Attendre après le clic
        print(f"   ✅ Enregistré!")

        return True


class ReferenceStrategy(ReplacementStrategy):
    """
    Stratégie pour les éléments de type "Référence(s)" qui utilisent valListeLibre

    UTILISÉ POUR: Référence(s) n° X dans les Notes de présentation, Rapports, etc.
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les éléments contenant 'Référence(s)' - DÉSACTIVÉE (géré par SquareEditStrategy)"""
        import re
        return False  # Désactivé - les Références sont maintenant gérées par SquareEditStrategy

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence de type Référence

        Les références utilisent un système similaire aux Attendus mais avec valListeLibre
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Exécuter goVariable()
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")
        await page.wait_for_timeout(2000)

        # Extraire les variables de old_pattern et new_pattern
        var_match = re.search(r'{@([^@]+)@}', old_pattern)
        if not var_match:
            print(f"   ❌ Pattern invalide: {old_pattern}")
            return False
        old_var = var_match.group(1)

        new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
        if not new_var_match:
            print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
            return False
        new_var = new_var_match.group(1)

        # Pour les Références, le textarea Summernote a un ID basé sur param1 avec "Editeur" ajouté
        # Ex: param1 = valListeLibre4373210_0_0_REFERENCE_2 -> textarea = valListeLibreEditeur4373210_0_0_REFERENCE_2
        textarea_id = param1.replace('valListeLibre', 'valListeLibreEditeur')
        print(f"   🔍 Textarea Summernote: #{textarea_id}")

        # Cliquer sur le conteneur pour activer l'éditeur Summernote
        print(f"   👆 Activation de l'éditeur (clic sur le conteneur)...")
        clicked = await page.evaluate(f'''() => {{
            const container = document.getElementById('{param1}');
            if (container) {{
                container.click();
                return true;
            }}
            return false;
        }}''')

        if not clicked:
            print(f"   ❌ Conteneur #{param1} non trouvé")
            return False

        await page.wait_for_timeout(1000)

        # Remplacer via Summernote API
        print(f"   ✏️  Remplacement via API Summernote...")
        replaced = await page.evaluate(f'''() => {{
            const textarea = document.getElementById('{textarea_id}');
            if (!textarea) {{
                console.log('Textarea non trouvé: {textarea_id}');
                return -1;
            }}

            if (!$(textarea).data('summernote')) {{
                console.log('Summernote non initialisé sur:', textarea.id);
                return -2;
            }}

            let content = $(textarea).summernote('code');
            let replacements = 0;

            // Patterns de remplacement
            const oldVar = '{old_var}';
            const newVar = '{new_var}';
            const oldVarEscaped = oldVar.replace(/[.*+?^${{}}()|[\\]\\\\]/g, '\\\\$&');

            const patterns = [
                {{ regex: new RegExp('\\\\{{@' + oldVarEscaped + '@([^}}]*)\\\\}}', 'g'), replacement: '{{@' + newVar + '@$1}}' }},
                {{ regex: new RegExp('\\\\{{@' + oldVarEscaped + '_en_lettres@([^}}]*)\\\\}}', 'g'), replacement: '{{@' + newVar + '_en_lettres@$1}}' }},
                {{ regex: new RegExp('\\\\{{@SI_' + oldVarEscaped + '@([^}}]*)\\\\}}', 'g'), replacement: '{{@SI_' + newVar + '@$1}}' }},
                {{ regex: new RegExp('\\\\{{@/SI_' + oldVarEscaped + '@([^}}]*)\\\\}}', 'g'), replacement: '{{@/SI_' + newVar + '@$1}}' }},
                {{ regex: new RegExp('\\\\{{@SI_NON_' + oldVarEscaped + '@([^}}]*)\\\\}}', 'g'), replacement: '{{@SI_NON_' + newVar + '@$1}}' }},
                {{ regex: new RegExp('\\\\{{@/SI_NON_' + oldVarEscaped + '@([^}}]*)\\\\}}', 'g'), replacement: '{{@/SI_NON_' + newVar + '@$1}}' }}
            ];

            for (const pattern of patterns) {{
                const matches = content.match(pattern.regex);
                if (matches) {{
                    replacements += matches.length;
                    content = content.replace(pattern.regex, pattern.replacement);
                }}
            }}

            if (replacements > 0) {{
                $(textarea).summernote('code', content);
            }}

            return replacements;
        }}''')

        if replaced == -1:
            print(f"   ❌ Textarea #{textarea_id} non trouvé")
            return False
        elif replaced == -2:
            print(f"   ❌ Summernote non initialisé")
            return False
        elif replaced > 0:
            print(f"   🔄 {replaced} remplacement(s) effectué(s)")
            # Déclencher la sauvegarde (blur sur .note-editable)
            print(f"   💾 Déclenchement de la sauvegarde (blur)...")
            await page.evaluate(f'''() => {{
                const textarea = document.getElementById('{textarea_id}');
                if (textarea) {{
                    const editable = $(textarea).next('.note-editor').find('.note-editable');
                    if (editable.length) {{
                        editable.blur();
                    }}
                }}
            }}''')
            await page.wait_for_timeout(500)
            return True
        else:
            print(f"   ⚠️  Aucun remplacement dans ce textarea")
            return False


class SimpleSummernoteStrategy(ReplacementStrategy):
    """
    Stratégie pour les éléments de type "Attendus (Vu)" utilisant Summernote simple

    PHILOSOPHIE:
    - Interface Lexpol: Zone de texte affichée en mode lecture (texte brut substitué)
    - Activation: Simple clic sur le conteneur pour activer Summernote
    - Édition: Éditeur WYSIWYG Summernote qui apparaît directement
    - Sauvegarde: Auto-save via événement blur (pas de bouton)

    IMPLÉMENTATION:
    - Clique sur le conteneur pour activer Summernote
    - Identifie le textarea caché par transformation d'ID (valAttendus → valAttendusEditeur)
    - Remplace via API Summernote.code() avec regex pour préserver les suffixes
    - Déclenche blur sur .note-editable pour sauvegarder automatiquement

    PARTICULARITÉ:
    - Pas besoin de bouton d'activation (différent de Article/Préambule qui ont f_edit.png)
    - Le textarea est caché (style="display: none") car Summernote gère l'affichage

    UTILISÉ POUR: Attendus (Vu) dans les éléments
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les éléments contenant 'Attendus (Vu)' - DÉSACTIVÉE (géré par SquareEditStrategy)"""
        import re
        return False  # Désactivé - les Attendus (Vu) sont maintenant gérés par SquareEditStrategy

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence de type Attendus (Vu) avec Summernote simple

        Process:
        1. Exécute goVariable() pour afficher la section
        2. Clique sur le texte de présentation pour activer l'éditeur Summernote
        3. Remplace le contenu via Summernote API avec support des suffixes Lexpol
        4. Déclenche blur pour sauvegarder
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Exécuter goVariable()
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")
        await page.wait_for_timeout(2000)

        # Extraire les variables de old_pattern et new_pattern
        var_match = re.search(r'{@([^@]+)@}', old_pattern)
        if not var_match:
            print(f"   ❌ Pattern invalide: {old_pattern}")
            return False
        old_var = var_match.group(1)

        new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
        if not new_var_match:
            print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
            return False
        new_var = new_var_match.group(1)

        # Pour les "Attendus (Vu)", le textarea Summernote a un ID basé sur param1 avec "Editeur" ajouté
        # Ex: param1 = valAttendus4284854_0_0_ATTENDUS_8 -> textarea = valAttendusEditeur4284854_0_0_ATTENDUS_8
        # On insère "Editeur" après "valAttendus"
        textarea_id = param1.replace('valAttendus', 'valAttendusEditeur')
        print(f"   🔍 Textarea Summernote: #{textarea_id}")

        # Cliquer sur le texte de présentation pour activer l'éditeur Summernote
        print(f"   👆 Activation de l'éditeur (clic sur le texte)...")
        clicked = await page.evaluate(f'''() => {{
            const container = document.getElementById('{param1}');
            if (!container) return false;
            container.click();
            return true;
        }}''')

        if not clicked:
            print(f"   ❌ Impossible de cliquer sur le conteneur")
            return False

        await page.wait_for_timeout(2000)  # Augmenté à 2s pour laisser Summernote s'initialiser

        # Faire le remplacement via l'API Summernote
        print(f"   ✏️  Remplacement via API Summernote...")
        result = await page.evaluate(f'''() => {{
            const ta = document.getElementById('{textarea_id}');
            if (!ta) return {{ success: false, count: 0, error: 'Textarea not found' }};

            // Vérifier si Summernote est initialisé
            if (typeof $('#{textarea_id}').summernote !== 'function') {{
                return {{ success: false, count: 0, error: 'Summernote not initialized' }};
            }}

            // Obtenir le contenu actuel via l'API Summernote
            let currentContent = $('#{textarea_id}').summernote('code');

            // Les variables à remplacer
            const oldVar = '{old_var}';
            const newVar = '{new_var}';

            // Compter et remplacer avec replaceAll (simple string replacement, pas de regex)
            let newContent = currentContent;
            let totalCount = 0;

            // Pattern 1: {{@old_var@}}
            const pattern1 = '{{@' + oldVar + '@}}';
            const replacement1 = '{{@' + newVar + '@}}';
            const count1 = (currentContent.split(pattern1).length - 1);
            if (count1 > 0) {{
                newContent = newContent.replaceAll(pattern1, replacement1);
                totalCount += count1;
            }}

            // Pattern 2: {{@old_var_en_lettres@}}
            const pattern2 = '{{@' + oldVar + '_en_lettres@}}';
            const replacement2 = '{{@' + newVar + '_en_lettres@}}';
            const count2 = (newContent.split(pattern2).length - 1);
            if (count2 > 0) {{
                newContent = newContent.replaceAll(pattern2, replacement2);
                totalCount += count2;
            }}

            if (totalCount > 0) {{
                // Mettre à jour via l'API Summernote
                $('#{textarea_id}').summernote('code', newContent);

                // IMPORTANT: Déclencher l'événement blur pour sauvegarder
                $('#{textarea_id}').next('.note-editor').find('.note-editable').trigger('blur');
            }}

            return {{ success: true, count: totalCount }};
        }}''')

        if not result['success']:
            error_msg = result.get('error', 'Unknown error')
            print(f"   ❌ Échec du remplacement: {error_msg}")
            return False

        count = result['count']

        if count == 0:
            print(f"   ⚠️  Aucun remplacement nécessaire (variable '{old_var}' non trouvée)")
            return False

        print(f"   🔄 {count} remplacement(s) effectué(s)")
        print(f"   ✅ Contenu remplacé via Summernote")
        print(f"   💾 Déclenchement de la sauvegarde (blur)...")
        await page.wait_for_timeout(2000)

        return True


class SummernoteStrategy(ReplacementStrategy):
    """
    Stratégie pour les éléments de type Contenu utilisant l'éditeur Summernote

    PHILOSOPHIE:
    - Interface Lexpol: Zone WYSIWYG riche avec texte formaté
    - Activation: Pour Article/Préambule → clic f_edit.png ; Pour Contenu → toujours actif
    - Édition: Éditeur WYSIWYG Summernote (HTML enrichi)
    - Sauvegarde: Auto-save via événement blur sur .note-editable

    IMPLÉMENTATION:
    - Détecte le type (Article/Préambule nécessite activation, Contenu déjà actif)
    - Scroll manuel obligatoire car goVariable() ne scroll pas pour Summernote
    - Pour Contenu: BUG LEXPOL - le lien ne précise pas le numéro exact du textarea
      → Solution: Traiter TOUS les textareas qui correspondent à la base ID
    - Remplace via API Summernote.code() avec regex pour préserver les suffixes
    - Déclenche blur sur .note-editable pour sauvegarder

    PARTICULARITÉS:
    - Article/Préambule: Nécessite activation/désactivation via f_edit.png
    - Contenu: Peut avoir plusieurs textareas (N1, N2, N3...) à traiter
    - Textarea caché (display: none), Summernote crée une div .note-editor visible

    UTILISÉ POUR: Contenu, Article, Préambule des éléments
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les éléments utilisant l'éditeur Summernote"""
        import re

        # Vérifier les patterns (avec ou sans numéro)
        patterns = [
            r'Contenu( n° \d+)?',
            r'Preambule( n° \d+)?',
            r'Article( n° \d+)?'
        ]

        return any(re.search(pattern, occurrence_text) for pattern in patterns)

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence de type Contenu avec Summernote

        Process:
        1. Exécute goVariable() pour afficher la section
        2. Pour Article/Préambule: Active l'éditeur en cliquant sur f_edit.png si nécessaire
        3. Scroll manuel vers l'élément (goVariable ne scroll pas pour Summernote)
        4. Trouve le textarea caché (style="display: none;")
        5. Remplace le contenu via Summernote API avec support des suffixes Lexpol
        6. Enregistre les modifications (trigger blur)
        7. Pour Article/Préambule: Désactive l'éditeur en cliquant sur f_edit.png
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Exécuter goVariable() et attendre que l'élément soit visible
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")

        # Attendre que l'élément cible soit prêt (au lieu d'un timeout fixe de 2s)
        element_ready = await wait_for_element_ready(page, f'#{param1}', timeout=3000)
        if not element_ready:
            print(f"   ⚠️  Élément #{param1} non trouvé, tentative de continuer...")
            await page.wait_for_timeout(300)  # Court fallback

        # Détecter si c'est un Article ou Préambule (nécessite activation de l'éditeur)
        is_article_or_preambule = 'Article' in occurrence['text'] or 'Preambule' in occurrence['text']

        # SCROLL MANUEL vers l'élément (le scroll automatique ne fonctionne pas)
        print(f"   📜 Scroll vers l'élément...")
        if param2:
            # Essayer de scroller vers l'élément du second paramètre
            scrolled = await page.evaluate(f'''() => {{
                const element = document.getElementById('{param2}');
                if (element) {{
                    element.scrollIntoView({{ behavior: 'smooth', block: 'center' }});
                    return true;
                }}
                return false;
            }}''')

            if not scrolled:
                # Fallback: essayer avec le premier paramètre + "1"
                await page.evaluate(f'''() => {{
                    const table = document.getElementById('{param1}1');
                    if (table) {{
                        table.scrollIntoView({{ behavior: 'smooth', block: 'center' }});
                    }}
                }}''')

        # Court délai après scroll (réduit de 2000ms à 300ms car l'élément est déjà vérifié)
        await page.wait_for_timeout(300)

        # DÉTECTION DE CONDITION (pour Article/Préambule/Contenu)
        # APPROCHE GÉNÉRIQUE basée sur la structure DOM
        print(f"   🔍 Vérification de condition...")
        condition_info = await page.evaluate(f'''() => {{
            const element = document.getElementById('{param1}');
            if (!element) return null;

            let conditionBtn = null;

            // Méthode 1: Chercher directement dans le container (Article/Préambule)
            conditionBtn = element.querySelector('a.btnCondition[id^="btnCondition_"]');

            // Méthode 2: Remonter au TR parent et chercher dedans (Contenu)
            if (!conditionBtn) {{
                const tr = element.closest('tr');
                if (tr) {{
                    conditionBtn = tr.querySelector('a.btnCondition[id^="btnCondition_"]');
                }}
            }}

            if (!conditionBtn) return null;

            const idCondition = conditionBtn.getAttribute('data-idcondition');
            const title = conditionBtn.getAttribute('title');

            return {{
                hasCondition: idCondition && idCondition !== "0",
                title: title || "",
                idCondition: idCondition
            }};
        }}''')

        if condition_info and condition_info['hasCondition']:
            # Vérifier si notre variable est dans la condition
            if old_pattern in condition_info['title']:
                element_type = 'article' if is_article_or_preambule else 'contenu'
                print(f"   ✅ Variable détectée dans la condition de {element_type}")
                print(f"   ℹ️  Condition: {condition_info['title']}")
                print(f"   ⏭️  Pas de remplacement nécessaire (condition auto-mise à jour)")
                return True

        # Pour Article/Préambule uniquement: Traiter le titre si nécessaire
        if is_article_or_preambule:
            # Extraire les variables de old_pattern et new_pattern (nécessaire pour le titre ET le contenu)
            var_match = re.search(r'{@([^@]+)@}', old_pattern)
            if not var_match:
                print(f"   ❌ Pattern invalide: {old_pattern}")
                return False
            old_var = var_match.group(1)

            new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
            if not new_var_match:
                print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
                return False
            new_var = new_var_match.group(1)

            # TRAITEMENT DU TITRE D'ARTICLE
            # ÉTAPE 1 : Activer le titre (clic sur span pour afficher l'éditeur Summernote)
            print(f"   🔍 Activation du titre d'article...")
            titre_activated = await page.evaluate(f'''() => {{
                const titreSpan = document.getElementById('{param1}_apercu_titre');
                if (!titreSpan) return {{ success: false, reason: 'Span titre non trouvé' }};

                const onclick = titreSpan.getAttribute('onclick');
                if (!onclick) return {{ success: false, reason: 'Pas de onclick sur le titre' }};

                // Exécuter le onclick pour activer le titre
                try {{
                    eval(onclick);
                    return {{ success: true }};
                }} catch (e) {{
                    return {{ success: false, reason: 'Erreur lors de l\\'activation: ' + e.message }};
                }}
            }}''')

            if not titre_activated or not titre_activated.get('success'):
                print(f"   ℹ️  {titre_activated.get('reason', 'Impossible activer le titre')}")
            else:
                # Attendre que Summernote soit initialisé
                await page.wait_for_timeout(1000)

            # ÉTAPE 2 : Vérifier si le titre contient la variable
            print(f"   🔍 Vérification du contenu du titre...")
            titre_info = await page.evaluate(f'''() => {{
                // Chercher le conteneur titre Summernote
                const titreContainer = document.getElementById('{param1}_contenu_titre');
                if (!titreContainer) return {{ hasTitre: false, reason: 'Conteneur titre non trouvé' }};

                // Vérifier si visible
                const isVisible = titreContainer.style.display !== 'none';
                if (!isVisible) return {{ hasTitre: false, reason: 'Conteneur titre non visible (display: none)' }};

                // Chercher l'éditeur Summernote du titre
                const editable = titreContainer.querySelector('.note-editable[contenteditable="true"]');
                if (!editable) return {{ hasTitre: false, reason: 'Éditeur Summernote titre non trouvé' }};

                // Lire le contenu HTML (pas textContent qui est rendu)
                const htmlContent = editable.innerHTML || '';

                // Vérifier si le HTML contient des variables Lexpol
                const hasVariable = htmlContent.includes('{{@');

                return {{
                    hasTitre: true,
                    hasVariable: hasVariable,
                    htmlContent: htmlContent,
                    textPreview: editable.textContent.substring(0, 100)
                }};
            }}''')

            # Debug : afficher les informations du titre
            # Chercher la variable SANS le } final pour gérer les suffixes (:minuscules, etc.)
            old_pattern_search = f'{{@{old_var}@'

            if titre_info is None:
                print(f"   ⚠️  titre_info est NULL (container '{param1}' introuvable)")
            elif not titre_info.get('hasTitre'):
                print(f"   ℹ️  {titre_info.get('reason', 'Titre non accessible')}")
            elif titre_info.get('hasVariable'):
                # Il y a des variables, mais peut-être pas la nôtre
                if old_pattern_search in titre_info.get('htmlContent', ''):
                    print(f"   ✅ Variable trouvée dans le titre: {titre_info['textPreview']}...")
                else:
                    print(f"   ℹ️  Titre contient des variables mais pas '{old_var}' (aperçu: {titre_info['textPreview'][:80]}...)")
            else:
                print(f"   ℹ️  Titre sans variable (aperçu: {titre_info.get('textPreview', 'N/A')[:80]}...)")

            # Vérifier en Python aussi si notre variable spécifique est dans le titre (avec support des suffixes)
            if titre_info and titre_info.get('hasTitre') and titre_info.get('hasVariable') and old_pattern_search in titre_info.get('htmlContent', ''):
                print(f"   📝 Traitement du titre d'article...")

                # Échapper correctement les noms de variables pour éviter les erreurs JS avec apostrophes
                old_var_escaped = json.dumps(old_var)
                new_var_escaped = json.dumps(new_var)
                param1_escaped = json.dumps(param1)

                # Le titre est dans un conteneur spécifique : article4373208_31_8_contenu_titre
                # Il faut chercher le .note-editable DANS ce conteneur
                replaced_titre = await page.evaluate(f'''() => {{
                    // Trouver le conteneur titre spécifique à cet article
                    const titreContainer = document.getElementById({param1_escaped} + '_contenu_titre');
                    if (!titreContainer) {{
                        console.log('Conteneur titre non trouvé');
                        return 0;
                    }}

                    // Chercher le .note-editable DANS ce conteneur
                    const editable = titreContainer.querySelector('.note-editable[contenteditable="true"]');
                    if (!editable) {{
                        console.log('Éditeur Summernote non trouvé dans le conteneur titre');
                        return 0;
                    }}

                    console.log('✅ Éditeur titre trouvé:', editable.textContent.substring(0, 50));

                    let content = editable.innerHTML;
                    let replacements = 0;

                    // Patterns de remplacement (mêmes que pour le contenu)
                    const oldVar = {old_var_escaped};
                    const newVar = {new_var_escaped};
                    const oldVarEscaped = oldVar.replace(/[.*+?^${{}}()|[\\]\\\\]/g, '\\\\$&');

                    const patterns = [
                        // Patterns simples
                        {{ regex: new RegExp('\\\\{{@' + oldVarEscaped + '@([^}}]*)\\\\}}', 'g'), replacement: '{{@' + newVar + '@$1}}' }},
                        {{ regex: new RegExp('\\\\{{@' + oldVarEscaped + '_en_lettres@([^}}]*)\\\\}}', 'g'), replacement: '{{@' + newVar + '_en_lettres@$1}}' }},

                        // Patterns booléens SI
                        {{ regex: new RegExp('\\\\{{@SI_' + oldVarEscaped + '@([^}}]*)\\\\}}', 'g'), replacement: '{{@SI_' + newVar + '@$1}}' }},
                        {{ regex: new RegExp('\\\\{{@/SI_' + oldVarEscaped + '@([^}}]*)\\\\}}', 'g'), replacement: '{{@/SI_' + newVar + '@$1}}' }},

                        // Patterns booléens SI_NON
                        {{ regex: new RegExp('\\\\{{@SI_NON_' + oldVarEscaped + '@([^}}]*)\\\\}}', 'g'), replacement: '{{@SI_NON_' + newVar + '@$1}}' }},
                        {{ regex: new RegExp('\\\\{{@/SI_NON_' + oldVarEscaped + '@([^}}]*)\\\\}}', 'g'), replacement: '{{@/SI_NON_' + newVar + '@$1}}' }}
                    ];

                    for (const pattern of patterns) {{
                        const matches = content.match(pattern.regex);
                        if (matches) {{
                            replacements += matches.length;
                            content = content.replace(pattern.regex, pattern.replacement);
                        }}
                    }}

                    if (replacements > 0) {{
                        editable.innerHTML = content;
                    }}

                    return replacements;
                }}''')

                if replaced_titre > 0:
                    print(f"   🔄 {replaced_titre} remplacement(s) dans le titre")
                    # Sauvegarder en cliquant en dehors
                    await page.keyboard.press('Escape')
                    await page.wait_for_timeout(300)
                else:
                    print(f"   ⚠️  Aucun remplacement dans le titre (malgré détection)")
                    await page.keyboard.press('Escape')
                    await page.wait_for_timeout(300)

        # Pour Article/Préambule: Activer l'éditeur si nécessaire
        edit_onclick = None
        if is_article_or_preambule:
            print(f"   🔓 Activation de l'éditeur (Article/Préambule)...")
            # Chercher le bouton f_edit.png dans la zone visible
            edit_onclick = await page.evaluate(f'''() => {{
                // Chercher l'image f_edit.png dans la zone param1
                const container = document.getElementById('{param1}');
                if (!container) return null;

                const editImg = container.querySelector('img[src*="f_edit.png"]');
                if (!editImg) return null;

                const link = editImg.closest('a');
                return link ? link.getAttribute('onclick') : null;
            }}''')

            if edit_onclick:
                print(f"   👆 Clic sur f_edit.png pour activer l'éditeur...")
                await page.evaluate(edit_onclick)

                # Attendre que l'éditeur Summernote soit initialisé (réduit de 3000ms)
                # On attend que la div .note-editor apparaisse
                summernote_ready = await wait_for_element_ready(page, '.note-editor', timeout=4000)
                if not summernote_ready:
                    print(f"   ⚠️  Éditeur Summernote non détecté, fallback...")
                    await page.wait_for_timeout(500)
            else:
                print(f"   ⚠️  Bouton f_edit.png non trouvé (peut-être déjà actif?)")
        else:
            # Si ce n'est pas un Article/Préambule, on doit quand même extraire les variables
            var_match = re.search(r'{@([^@]+)@}', old_pattern)
            if not var_match:
                print(f"   ❌ Pattern invalide: {old_pattern}")
                return False
            old_var = var_match.group(1)

            new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
            if not new_var_match:
                print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
                return False
            new_var = new_var_match.group(1)

        # Pattern de recherche : {@variable@ (sans } pour capturer les suffixes)
        old_pattern_search = f'{{@{old_var}@'
        old_pattern_lettres_search = f'{{@{old_var}_en_lettres@'

        # IMPORTANT: Chercher TOUJOURS par ID (pas par contenu)
        # car en mode présentation Lexpol a déjà fait le remplacement visuel
        print(f"   🔍 Recherche du textarea Summernote (par ID, pas par contenu)...")

        if is_article_or_preambule:
            # Pour un article/préambule, le textarea du contenu est {param1}_txt
            # Ex: article4284856_31_6 -> article4284856_31_6_txt
            textarea_ids = [f"{param1}_txt"]
        else:
            # Pour les Contenu: PROBLÈME LEXPOL - le lien ne précise pas le numéro (bug)
            # Ex: lien dit MULTI_4284867_0_0_CONTENU_ mais il peut y avoir _1, _2, _3, _4...
            # SOLUTION: Traiter TOUS les textareas qui correspondent à cette base
            print(f"   🔍 Recherche de TOUS les textareas Contenu (bug Lexpol)...")

            # Transformer MULTI_4284853_0_0_CONTENU_ en 4284853_0_0_CONTENU_
            base_id = param1.replace('MULTI_', '').rstrip('_')
            print(f"   🔍 Base ID: {base_id}_")

            # Chercher TOUS les textareas dont l'ID commence par cette base OU égal à base_id
            # (sans underscore final car parfois Lexpol met l'underscore, parfois non)
            textarea_ids = await page.evaluate(f'''() => {{
                const textareas = document.querySelectorAll('textarea.editeur');
                const ids = [];
                for (const ta of textareas) {{
                    if (ta.id && (ta.id === '{base_id}' || ta.id.startsWith('{base_id}_'))) {{
                        ids.push(ta.id);
                    }}
                }}
                return ids;
            }}''')

            if not textarea_ids or len(textarea_ids) == 0:
                print(f"   ❌ Aucun textarea Summernote trouvé")
                # Debug: lister TOUS les textareas disponibles
                print(f"   🐛 DEBUG: Listing tous les textareas avec classe 'editeur'...")
                all_textareas = await page.evaluate('''() => {
                    const textareas = document.querySelectorAll('textarea.editeur');
                    return Array.from(textareas).map(ta => ta.id || 'no-id');
                }''')
                print(f"   🐛 {len(all_textareas)} textareas trouvés: {all_textareas[:10]}")

                # Debug: lister TOUS les textareas (sans filtre de classe)
                print(f"   🐛 DEBUG: Listing TOUS les textareas (sans filtre)...")
                all_textareas_nofilter = await page.evaluate('''() => {
                    const textareas = document.querySelectorAll('textarea');
                    return Array.from(textareas).map(ta => ({ id: ta.id || 'no-id', className: ta.className }));
                }''')
                print(f"   🐛 {len(all_textareas_nofilter)} textareas au total")
                for ta in all_textareas_nofilter[:15]:
                    print(f"      - ID: {ta['id']}, Class: {ta['className']}")
                return False

            print(f"   ✅ {len(textarea_ids)} textarea(s) trouvé(s): {', '.join(textarea_ids)}")

        # Traiter chaque textarea (un seul pour Article/Préambule, potentiellement plusieurs pour Contenu)
        total_replacements = 0
        for i, textarea_id in enumerate(textarea_ids, 1):
            if len(textarea_ids) > 1:
                print(f"   📝 Traitement textarea {i}/{len(textarea_ids)}: #{textarea_id}")

            # Vérifier d'abord si ce textarea contient la variable (pour les Contenu multiples)
            if not is_article_or_preambule and len(textarea_ids) > 1:
                # Vérifier si ce textarea contient bien la variable avant de remplacer
                contains_var = await page.evaluate('''(args) => {
                    const ta = document.getElementById(args.textareaId);
                    if (!ta) return false;
                    const content = $('#' + args.textareaId).summernote('code');
                    return content.includes('{@' + args.oldVar + '@') ||
                           content.includes('{@' + args.oldVar + '_en_lettres@') ||
                           content.includes('{@SI_' + args.oldVar + '@') ||
                           content.includes('{@/SI_' + args.oldVar + '@') ||
                           content.includes('{@SI_NON_' + args.oldVar + '@') ||
                           content.includes('{@/SI_NON_' + args.oldVar + '@');
                }''', {'textareaId': textarea_id, 'oldVar': old_var})

                if not contains_var:
                    print(f"      ⏭️  Variable non présente dans ce textarea, passage au suivant")
                    continue

            # Remplacer le contenu en utilisant l'API Summernote avec regex pour capturer les suffixes
            print(f"   ✏️  Remplacement via API Summernote...")
            result = await page.evaluate(r'''(args) => {
                const ta = document.getElementById(args.textareaId);
                if (!ta) return { success: false, count: 0, error: 'Textarea not found' };

                // Vérifier si Summernote est initialisé
                if (typeof $('#' + args.textareaId).summernote !== 'function') {
                    return { success: false, count: 0, error: 'Summernote not initialized' };
                }

                // Obtenir le contenu actuel via l'API Summernote
                let currentContent = $('#' + args.textareaId).summernote('code');

                // Échapper les caractères spéciaux pour regex
                const escapeRegex = (str) => str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                const oldVarEscaped = escapeRegex(args.oldVar);
                const newVar = args.newVar;

                // Compteurs
                let totalCount = 0;

                // Liste des patterns à remplacer (comme dans replace_variable_with_suffixes)
                const patterns = [
                    // Patterns simples
                    { regex: new RegExp('\\{@' + oldVarEscaped + '@([^}]*)\\}', 'g'), replacement: '{@' + newVar + '@$1}' },
                    { regex: new RegExp('\\{@' + oldVarEscaped + '_en_lettres@([^}]*)\\}', 'g'), replacement: '{@' + newVar + '_en_lettres@$1}' },

                    // Patterns booléens SI
                    { regex: new RegExp('\\{@SI_' + oldVarEscaped + '@([^}]*)\\}', 'g'), replacement: '{@SI_' + newVar + '@$1}' },
                    { regex: new RegExp('\\{@/SI_' + oldVarEscaped + '@([^}]*)\\}', 'g'), replacement: '{@/SI_' + newVar + '@$1}' },

                    // Patterns booléens SI_NON
                    { regex: new RegExp('\\{@SI_NON_' + oldVarEscaped + '@([^}]*)\\}', 'g'), replacement: '{@SI_NON_' + newVar + '@$1}' },
                    { regex: new RegExp('\\{@/SI_NON_' + oldVarEscaped + '@([^}]*)\\}', 'g'), replacement: '{@/SI_NON_' + newVar + '@$1}' }
                ];

                // Appliquer tous les patterns
                for (const pattern of patterns) {
                    try {
                        const matches = currentContent.match(pattern.regex);
                        if (matches) {
                            totalCount += matches.length;
                            currentContent = currentContent.replace(pattern.regex, pattern.replacement);
                        }
                    } catch (e) {
                        console.error('Erreur pattern:', e);
                    }
                }

                if (totalCount > 0) {
                    // Mettre à jour via l'API Summernote
                    $('#' + args.textareaId).summernote('code', currentContent);

                    // IMPORTANT: Déclencher l'événement blur pour sauvegarder
                    $('#' + args.textareaId).next('.note-editor').find('.note-editable').trigger('blur');
                }

                return {
                    success: true,
                    count: totalCount,
                    contentPreview: currentContent.substring(0, 500),
                    contentLength: currentContent.length,
                    hasOldVar: currentContent.includes('{@' + args.oldVar + '@') ||
                               currentContent.includes('{@SI_' + args.oldVar + '@') ||
                               currentContent.includes('{@SI_NON_' + args.oldVar + '@')
                };
            }''', {'textareaId': textarea_id, 'oldVar': old_var, 'newVar': new_var})

            if not result['success']:
                error_msg = result.get('error', 'Unknown error')
                print(f"   ❌ Échec du remplacement via API Summernote: {error_msg}")
                continue

            count = result['count']

            # Debug: afficher les informations sur le contenu
            if count == 0:
                print(f"   ⚠️  Aucun remplacement dans ce textarea")
                print(f"   🔍 DEBUG - Contenu du textarea:")
                print(f"      - Longueur: {result.get('contentLength', 0)} caractères")
                print(f"      - Contient la variable? {result.get('hasOldVar', False)}")
                print(f"      - Aperçu (500 premiers caractères):")
                preview = result.get('contentPreview', '')
                for line in preview.split('\n')[:5]:
                    print(f"        {line}")

                # Afficher le contenu complet pour trouver la variable
                full_content = await page.evaluate(f'''() => {{
                    return $('#{textarea_id}').summernote('code');
                }}''')
                print(f"   📄 CONTENU COMPLET:")
                print(full_content)
                continue

            total_replacements += count
            print(f"   🔄 {count} remplacement(s) effectué(s)")
            print(f"   ✅ Contenu remplacé via Summernote")
            print(f"   💾 Déclenchement de la sauvegarde (blur)...")
            await page.wait_for_timeout(2000)

        # Fin de la boucle - vérifier s'il y a eu des remplacements
        if total_replacements == 0:
            print(f"   ⚠️  Aucun remplacement effectué au total")
            # Désactiver l'éditeur si on l'a activé
            if is_article_or_preambule and edit_onclick:
                print(f"   🔒 Désactivation de l'éditeur (Article/Préambule)...")
                await page.evaluate(edit_onclick)
                await page.wait_for_timeout(1000)
            return False

        print(f"   🎉 Total: {total_replacements} remplacement(s) effectué(s)")

        # Pour Article/Préambule: Désactiver l'éditeur en recliquant sur f_edit.png
        if is_article_or_preambule and edit_onclick:
            print(f"   🔒 Désactivation de l'éditeur (Article/Préambule)...")
            await page.evaluate(edit_onclick)
            await page.wait_for_timeout(1000)

        return True


class CCBFModalStrategy(ReplacementStrategy):
    """
    Stratégie pour les éléments de type "Informations relatives au passage en CCBF"

    PHILOSOPHIE:
    - Interface Lexpol: Affichage en lecture seule des informations CCBF
    - Activation: Clic sur square_edit.png ouvre une popup modale
    - Édition: Formulaire avec multiples champs input dans la modal (#simplemodal-container)
    - Sauvegarde: Clic sur bouton "Enregistrer" (#valider-aide_fin)

    IMPLÉMENTATION:
    - Clique sur square_edit.png pour ouvrir la popup modale
    - Attend que #simplemodal-container soit visible
    - Parcourt TOUS les champs input possibles (liste hardcodée)
    - Remplace avec support des suffixes dans chaque champ contenant la variable
    - Clique sur "Enregistrer" pour fermer et sauvegarder

    PARTICULARITÉS:
    - Popup modale (overlay) qui masque le reste de la page
    - 15 champs input différents possibles (ccbfIsUrgVariable, dbfOrganisme, etc.)
    - Nécessite traitement de TOUS les champs car la variable peut être dans n'importe lequel

    UTILISÉ POUR: Informations relatives au passage en CCBF
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les éléments contenant 'Informations relatives au passage en CCBF'"""
        return "Informations relatives au passage en CCBF" in occurrence_text

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence de type CCBF avec popup modale

        Process:
        1. Exécute goVariable() pour afficher la section
        2. Trouve et clique sur square_edit.png pour ouvrir la popup
        3. Attend que la popup modale s'affiche
        4. Parcourt TOUS les champs input de la popup
        5. Remplace avec support des suffixes Lexpol dans chaque champ
        6. Clique sur "Enregistrer"
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Exécuter goVariable()
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")
        await page.wait_for_timeout(2000)

        # Extraire les variables de old_pattern et new_pattern
        var_match = re.search(r'{@([^@]+)@}', old_pattern)
        if not var_match:
            print(f"   ❌ Pattern invalide: {old_pattern}")
            return False
        old_var = var_match.group(1)

        new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
        if not new_var_match:
            print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
            return False
        new_var = new_var_match.group(1)

        # Pattern de recherche : {@variable@ (sans } pour capturer les suffixes)
        old_pattern_search = f'{{@{old_var}@'
        old_pattern_lettres_search = f'{{@{old_var}_en_lettres@'

        # Trouver le square_edit dans la section affichée
        print(f"   🔍 Recherche du bouton d'édition...")
        edit_button = await page.query_selector(f'a[onclick*="modifierAideFinanciere"] img[src*="square_edit.png"]')

        if not edit_button:
            print(f"   ❌ Bouton d'édition non trouvé")
            return False

        # Cliquer pour ouvrir la popup modale
        print(f"   👆 Ouverture de la popup modale...")
        await edit_button.click()
        await page.wait_for_timeout(1500)

        # Attendre que la popup modale soit visible
        modal = await page.wait_for_selector('#simplemodal-container', timeout=5000)
        if not modal:
            print(f"   ❌ Popup modale non trouvée")
            return False

        print(f"   ✅ Popup modale ouverte")

        # Liste de tous les champs input possibles dans la popup
        input_ids = [
            'ccbfIsUrgVariable',
            'ccbfIsCapVariable',
            'ccbfIsNomVariable',
            'ccbfIsAideVariable',
            'ccbfIsCCBFVariable',
            'dbfOrganismeVar',
            'dbfOrganisme',
            'dbfNumTahiti',
            'dbfMontant',
            'dbfProgramme',
            'ccbf_lettre_num',
            'ccbf_lettre_date',
            'ccbf_lettre_reception',
            'ccbf_avis_num',
            'ccbf_avis_date'
        ]

        # Parcourir tous les champs et remplacer les patterns avec support des suffixes
        total_replacements = 0

        for input_id in input_ids:
            input_elem = await page.query_selector(f'#{input_id}')
            if not input_elem:
                continue

            # Lire la valeur actuelle
            current_value = await input_elem.input_value()
            if not current_value:
                continue

            # Vérifier si le pattern existe (recherche partielle)
            if old_pattern_search not in current_value and old_pattern_lettres_search not in current_value:
                continue

            # Appliquer les remplacements avec support des suffixes
            new_value, count = replace_variable_with_suffixes(current_value, old_var, new_var)

            if count == 0:
                continue

            # Remplir le champ avec la nouvelle valeur
            await input_elem.fill(new_value)
            total_replacements += count
            print(f"   ✏️  Champ #{input_id} modifié ({count} remplacement(s))")

        if total_replacements == 0:
            print(f"   ⚠️  Aucun remplacement nécessaire")
            # Fermer la popup sans enregistrer
            cancel_btn = await page.query_selector('#annuler-aide_fin')
            if cancel_btn:
                await cancel_btn.click()
                await page.wait_for_timeout(500)
            return False

        print(f"   🔄 {total_replacements} remplacement(s) effectué(s)")

        # Cliquer sur "Enregistrer" via JavaScript (force click)
        print(f"   💾 Enregistrement...")
        save_success = await page.evaluate('''() => {
            const btn = document.querySelector('#valider-aide_fin');
            if (!btn) return false;
            btn.click();
            return true;
        }''')

        if not save_success:
            print(f"   ❌ Bouton Enregistrer non trouvé")
            return False

        await page.wait_for_timeout(2000)
        print(f"   ✅ Enregistré!")

        return True


class SimpleTextareaStrategy(ReplacementStrategy):
    """
    Stratégie pour les textareas simples avec auto-save via blur

    PHILOSOPHIE:
    - Interface Lexpol: Textarea simple en lecture/écriture directe
    - Activation: Aucune (le textarea est toujours éditable)
    - Édition: Saisie directe dans le textarea (pas d'éditeur WYSIWYG)
    - Sauvegarde: Auto-save via événement blur (pas de bouton)

    IMPLÉMENTATION:
    - Cherche le textarea avec class="editeursimple" DANS le conteneur unique
    - CRITIQUE: Ne pas utiliser getElementById() car plusieurs textareas peuvent avoir le même ID
    - Récupère le textarea via evaluate_handle() depuis le conteneur
    - Remplace avec pattern Ctrl+A + Backspace + fill()
    - Déclenche blur directement sur le ElementHandle (pas via getElementById)

    PARTICULARITÉ:
    - PROBLÈME: Plusieurs documents peuvent avoir des textareas avec le même ID
      Exemple: "Courrier au demandeur" et "Mise en demeure" ont tous deux id="DESTINATAIRE_LETTRE"
    - SOLUTION: Chercher le textarea dans le conteneur unique (param1)
    - Utiliser le ElementHandle récupéré pour le blur (pas document.getElementById)

    UTILISÉ POUR: Référent du dossier, Mode de notification, Destinataire, Délai d'exécution, Dossier
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les textareas simples"""
        # Liste des suffixes compatibles avec cette stratégie
        compatible_suffixes = [
            "Référent du dossier",
            "Mode de notification",
            "Destinataire",
            "Délai d'exécution",
            "Dossier"
        ]
        return any(suffix in occurrence_text for suffix in compatible_suffixes)

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence avec simple textarea

        Process:
        1. Exécute goVariable() pour afficher la section
        2. Trouve le textarea avec class="editeursimple"
        3. Remplace le contenu avec support des suffixes Lexpol
        4. Déclenche blur pour sauvegarder automatiquement
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Exécuter goVariable()
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")
        await page.wait_for_timeout(2000)

        # Extraire les variables de old_pattern et new_pattern
        var_match = re.search(r'{@([^@]+)@}', old_pattern)
        if not var_match:
            print(f"   ❌ Pattern invalide: {old_pattern}")
            return False
        old_var = var_match.group(1)

        new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
        if not new_var_match:
            print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
            return False
        new_var = new_var_match.group(1)

        # Pattern de recherche : {@variable@ (sans } pour capturer les suffixes)
        old_pattern_search = f'{{@{old_var}@'
        old_pattern_lettres_search = f'{{@{old_var}_en_lettres@'

        # Chercher le textarea simple DANS LE CONTENEUR SPÉCIFIQUE
        # IMPORTANT: Ne pas utiliser l'ID du textarea car il peut être dupliqué entre documents
        # Il faut chercher le textarea à l'intérieur du conteneur unique
        print(f"   🔍 Recherche du textarea simple dans #{param1}...")

        # Utiliser JavaScript pour trouver le textarea dans le conteneur
        textarea_found = await page.evaluate(f'''() => {{
            const container = document.getElementById('{param1}');
            if (!container) {{
                console.log('Container not found: {param1}');
                return null;
            }}

            // Chercher le textarea avec class="editeursimple" dans ce conteneur
            const textarea = container.querySelector('textarea.editeursimple');
            if (!textarea) {{
                console.log('Textarea not found in container');
                return null;
            }}

            // Vérifier si le textarea contient la variable
            if (textarea.value && (textarea.value.includes('{old_pattern_search}') || textarea.value.includes('{old_pattern_lettres_search}'))) {{
                return {{ id: textarea.id, found: true }};
            }}

            return {{ id: textarea.id, found: false }};
        }}''')

        if not textarea_found:
            print(f"   ❌ Textarea simple non trouvé dans le conteneur")
            return False

        textarea_id = textarea_found['id']
        print(f"   ✅ Textarea simple: #{textarea_id} (dans #{param1})")

        # Récupérer le textarea DEPUIS LE CONTENEUR (pas par ID global)
        textarea = await page.evaluate_handle(f'''() => {{
            const container = document.getElementById('{param1}');
            if (!container) return null;
            return container.querySelector('textarea.editeursimple');
        }}''')

        # Vérifier que le handle pointe vers un élément valide
        is_valid = await textarea.evaluate('el => el !== null')
        if not is_valid:
            print(f"   ❌ Textarea inaccessible")
            return False

        # Convertir en ElementHandle
        textarea = textarea.as_element()

        # Lire la valeur actuelle
        old_value = await textarea.input_value()

        # Appliquer les remplacements avec support des suffixes
        new_value, total_count = replace_variable_with_suffixes(old_value, old_var, new_var)

        if total_count == 0:
            print(f"   ⚠️  Aucun remplacement nécessaire")
            return False

        print(f"   🔄 {total_count} remplacement(s) effectué(s)")

        # Remplir le textarea avec la nouvelle valeur
        print(f"   ✏️  Remplacement du contenu...")
        # IMPORTANT: Utiliser le pattern standard de remplacement
        await fill_textarea_with_clear(textarea, new_value)
        print(f"   ✅ Contenu remplacé")

        # Déclencher blur pour sauvegarder automatiquement
        # IMPORTANT: Utiliser directement le ElementHandle textarea (pas getElementById)
        # car il peut y avoir plusieurs textareas avec le même ID
        print(f"   💾 Déclenchement de la sauvegarde (blur)...")
        await textarea.evaluate('el => el.blur()')
        await page.wait_for_timeout(2000)
        print(f"   ✅ Sauvegardé!")

        return True


class EditableTableStrategy(ReplacementStrategy):
    """
    Stratégie pour les tableaux éditables avec cellules cliquables

    PHILOSOPHIE:
    - Interface Lexpol: Tableau avec cellules affichant du texte substitué
    - Activation: Clic sur cellule <p onclick> pour activer le textarea
    - Édition: Textarea apparaît dans la cellule pour édition
    - Sauvegarde: Auto-save via blur qui recharge la div entière

    IMPLÉMENTATION:
    - Approche générique basée sur <p onclick> (fonctionne pour tous les tableaux)
    - Collecte TOUS les IDs des <p onclick> AVANT toute modification
    - Pour chaque cellule: clique sur <p>, édite le textarea, déclenche blur
    - CRITIQUE: Après blur(), Lexpol recharge la div entière dans le DOM
    - Les IDs des <p> restent identiques malgré le rechargement
    - Utiliser document.getElementById() à chaque itération (pas de référence d'élément)

    PARTICULARITÉS:
    - DOM rechargé après chaque blur: Il faut re-chercher les éléments à chaque fois
    - IDs stables: Les IDs des <p onclick> ne changent pas lors du rechargement
    - Pattern Ctrl+A + Backspace + fill() pour garantir le remplacement
    - Test de re-collecte des IDs après la 1ère édition pour vérifier la stabilité

    TYPES DE TABLEAUX SUPPORTÉS:
    - Parties signataires (activeModifParties)
    - Autres parties signataires (activeModifParties)
    - Imputations budgétaires (activeModifImputations)
    - Tout tableau avec structure <p onclick> → textarea

    UTILISÉ POUR: Autre(s) partie(s) signataire(s), Partie(s) signataire(s), Imputations budgétaires
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les tableaux éditables avec cellules cliquables"""
        # Liste des suffixes compatibles avec cette stratégie
        compatible_suffixes = [
            "Autre(s) partie(s) signataire(s)",
            "Partie(s) signataire(s)",
            "Imputations budgétaires"
        ]
        return any(suffix in occurrence_text for suffix in compatible_suffixes)

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence avec tableau éditable (approche générique)

        Process:
        1. Exécute goVariable() pour afficher la section
        2. Trouve la div container puis le tableau à l'intérieur
        3. Parcourt TOUS les éléments <p onclick> du tableau (générique)
        4. Pour chaque <p> trouvé :
           - Clique dessus pour activer le textarea
           - Cherche le textarea qui apparaît (dans le <p> ou dans son parent)
           - Remplace le contenu avec support des suffixes Lexpol
           - Déclenche blur pour sauvegarder

        Cette approche est générique et fonctionne pour :
        - Parties signataires (activeModifParties)
        - Autres parties signataires (activeModifParties)
        - Imputations budgétaires (activeModifImputations)
        - Tout autre type de tableau avec <p onclick>
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Extraire le div_id depuis param1
        # Format: valeurChamp_4284856_PARTIES2 → 4284856_PARTIES2
        # Format: valeurChamp_4284855_IMPUTATIONS_BUDGETAIRES → 4284855_IMPUTATIONS_BUDGETAIRES
        div_id = param1.replace('valeurChamp_', '')
        print(f"   🔍 Div ID: {div_id}")

        # Exécuter goVariable()
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")
        print(f"   ⏳ Attente chargement (4s)...")
        await page.wait_for_timeout(4000)

        # Extraire les variables de old_pattern et new_pattern
        var_match = re.search(r'{@([^@]+)@}', old_pattern)
        if not var_match:
            print(f"   ❌ Pattern invalide: {old_pattern}")
            return False
        old_var = var_match.group(1)

        new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
        if not new_var_match:
            print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
            return False
        new_var = new_var_match.group(1)

        # Pattern de recherche : {@variable@ (sans } pour capturer les suffixes)
        old_pattern_search = f'{{@{old_var}@'
        old_pattern_lettres_search = f'{{@{old_var}_en_lettres@'

        # Trouver la div puis la table à l'intérieur (approche simplifiée)
        print(f"   🔍 Recherche de la div #{div_id}...")
        container = await page.query_selector(f'div[id="{div_id}"]')
        if not container:
            print(f"   ❌ Div non trouvée")
            return False

        print(f"   ✅ Div trouvée: {div_id}")

        # Chercher la table à l'intérieur de la div
        print(f"   🔍 Recherche de la table dans la div...")
        table = await container.query_selector('table')
        if not table:
            print(f"   ❌ Table non trouvée dans la div")
            return False

        # Récupérer l'ID de la table pour info
        table_id = await table.get_attribute('id')
        print(f"   ✅ Table trouvée: {table_id}")

        # Collecter TOUS les IDs des <p onclick> au début (avant toute modification du DOM)
        print(f"   🔍 Collecte de tous les IDs des cellules...")
        initial_cell_ids = await page.evaluate(f'''() => {{
            const container = document.getElementById('{div_id}');
            if (!container) return [];

            const table = container.querySelector('table');
            if (!table) return [];

            const allPs = Array.from(table.querySelectorAll('p[onclick]'));
            return allPs.map(p => p.getAttribute('id')).filter(id => id !== null);
        }}''')

        if len(initial_cell_ids) == 0:
            print(f"   ⚠️  Aucune cellule éditable trouvée")
            return False

        print(f"   ✅ {len(initial_cell_ids)} cellule(s) éditables trouvées")
        print(f"   📋 IDs initiaux: {initial_cell_ids[:3]}... (3 premiers)")

        # Traiter chaque cellule en utilisant son ID
        # NOTE: Les IDs restent les mêmes, mais la div/table est rechargée dans le DOM après chaque blur()
        # Il faut donc chercher le <p> par son ID à chaque itération (pas utiliser une référence d'élément)
        total_replacements = 0

        for i, p_id in enumerate(initial_cell_ids, 1):
            # IMPORTANT: Re-chercher le <p> dans le DOM actuel (la div a été rechargée après le blur précédent)
            # Utiliser document.getElementById() qui fonctionne même si le DOM a été rechargé
            clicked = await page.evaluate(f'''() => {{
                const p = document.getElementById('{p_id}');
                if (!p) {{
                    console.log('Element not found: {p_id}');
                    return false;
                }}
                p.click();
                return true;
            }}''')

            if not clicked:
                print(f"      ⚠️  Cellule {i}/{len(initial_cell_ids)}: <p> non trouvé (ID: {p_id})")
                continue

            await page.wait_for_timeout(200)

            # Trouver le textarea dans le <td>
            textarea_elem = await page.evaluate_handle(f'''() => {{
                const clickedP = document.getElementById('{p_id}');
                if (!clickedP) return null;
                const td = clickedP.closest('td');
                if (!td) return null;
                const ta = td.querySelector('textarea');
                if (ta && ta.offsetParent !== null) return ta;
                return null;
            }}''')

            # Vérifier que le handle pointe vers un élément valide
            is_valid = await textarea_elem.evaluate('el => el !== null')
            if not is_valid:
                continue

            # Convertir le JSHandle en ElementHandle
            textarea_elem = textarea_elem.as_element()

            # Lire la valeur actuelle
            old_value = await textarea_elem.input_value()

            # DEBUG: Afficher ce qui est dans le textarea
            if i <= 3 or (old_var in old_value):  # Afficher les 3 premiers + ceux qui contiennent la variable
                preview = old_value[:100] if old_value else "(vide)"
                print(f"      🔍 Cellule {i}: contenu = {preview}")
                if old_var in old_value:
                    print(f"         ✅ Variable '{old_var}' TROUVÉE dans le textarea")
                else:
                    print(f"         ⚠️  Variable '{old_var}' NON trouvée")

            # Appliquer les remplacements avec support des suffixes
            new_value, count = replace_variable_with_suffixes(old_value, old_var, new_var)

            if count > 0:
                print(f"      📝 Remplacement: '{old_value[:50]}' → '{new_value[:50]}'")
                # IMPORTANT: Utiliser le pattern standard de remplacement
                await fill_textarea_with_clear(textarea_elem, new_value)
                print(f"      ✅ Contenu écrit dans le textarea")

            # Fermer le textarea (blur)
            await page.evaluate(f'''() => {{
                const p = document.getElementById('{p_id}');
                if (p) {{
                    const td = p.closest('td');
                    if (td) {{
                        const ta = td.querySelector('textarea');
                        if (ta) ta.blur();
                    }}
                }}
            }}''')

            # IMPORTANT: Après blur(), Lexpol recharge la div entière
            # Attendre que le DOM soit rechargé avant de continuer
            await page.wait_for_timeout(500)  # Augmenté pour laisser le temps au rechargement

            # TEST : Re-collecter les IDs après la première cellule (blur) pour vérifier s'ils changent
            if i == 1:
                print(f"\n   🔬 TEST: Re-collecte des IDs après la 1ère édition...")
                current_cell_ids = await page.evaluate(f'''() => {{
                    const container = document.getElementById('{div_id}');
                    if (!container) return [];
                    const table = container.querySelector('table');
                    if (!table) return [];
                    const allPs = Array.from(table.querySelectorAll('p[onclick]'));
                    return allPs.map(p => p.getAttribute('id')).filter(id => id !== null);
                }}''')

                print(f"   📊 IDs initiaux : {len(initial_cell_ids)} cellules")
                print(f"   📊 IDs actuels  : {len(current_cell_ids)} cellules")

                if len(current_cell_ids) != len(initial_cell_ids):
                    print(f"   ⚠️  NOMBRE D'IDs DIFFÉRENT !")

                # Comparer les 3 premiers IDs
                print(f"   🔍 Comparaison des 3 premiers IDs:")
                for j in range(min(3, len(initial_cell_ids), len(current_cell_ids))):
                    initial = initial_cell_ids[j] if j < len(initial_cell_ids) else "N/A"
                    current = current_cell_ids[j] if j < len(current_cell_ids) else "N/A"
                    match = "✅" if initial == current else "❌"
                    print(f"      {match} [{j}] Initial: {initial}")
                    print(f"         [{j}] Actuel : {current}")

                # Vérifier si les IDs ont changé
                ids_changed = set(initial_cell_ids) != set(current_cell_ids)
                if ids_changed:
                    print(f"   ❌ LES IDs ONT CHANGÉ après la 1ère édition !")
                    # Montrer quelques différences
                    missing = set(initial_cell_ids) - set(current_cell_ids)
                    new = set(current_cell_ids) - set(initial_cell_ids)
                    if missing:
                        print(f"      IDs disparus: {list(missing)[:3]}...")
                    if new:
                        print(f"      Nouveaux IDs: {list(new)[:3]}...")
                else:
                    print(f"   ✅ Les IDs n'ont PAS changé")
                print()

            if count == 0:
                # Pas de variable ici, attendre et continuer
                await page.wait_for_timeout(300)
                continue

            total_replacements += count
            print(f"      ✅ Cellule {i}/{len(initial_cell_ids)}: {count} remplacement(s)")

            # Attendre 300ms avant le clic suivant
            await page.wait_for_timeout(300)

        if total_replacements == 0:
            print(f"   ⚠️  Aucun remplacement effectué")
            return False

        print(f"   🔄 {total_replacements} remplacement(s) effectué(s) au total")
        print(f"   ✅ Tous les textareas traités!")

        return True


class ButtonSaveStrategy(ReplacementStrategy):
    """
    Stratégie pour les textareas avec bouton 'Enregistrer'

    PHILOSOPHIE:
    - Interface Lexpol: Textarea désactivé par défaut avec icône square_edit.png
    - Activation: Clic sur square_edit.png pour activer l'édition
    - Édition: Le textarea devient éditable, l'utilisateur peut modifier
    - Sauvegarde: Clic sur bouton "Enregistrer" explicite (pas de blur auto)

    IMPLÉMENTATION:
    - Similaire à SquareEditStrategy mais avec bouton au lieu de re-clic sur square_edit
    - Trouve le textarea par son contenu
    - Clique sur square_edit.png pour activer
    - Remplace avec pattern Ctrl+A + Backspace + fill()
    - Dérive l'ID du bouton depuis l'ID du textarea (ex: _edit_txt → _save)
    - Clique sur le bouton "Enregistrer"

    DIFFÉRENCE AVEC SquareEditStrategy:
    - SquareEditStrategy: Re-clic sur square_edit pour sauvegarder
    - ButtonSaveStrategy: Bouton "Enregistrer" séparé pour sauvegarder

    UTILISÉ POUR: Intitulé du dossier, Référence interne, Commentaire, Référence courrier complémentaire
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les champs avec bouton Enregistrer"""
        import re

        patterns = [
            r'Intitulé du dossier',
            r'Référence interne',
            r'Commentaire',
            r'Référence courrier complémentaire'
        ]

        return any(re.search(pattern, occurrence_text) for pattern in patterns)

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence avec textarea + bouton Enregistrer

        Process:
        1. Exécute goVariable() pour afficher la section
        2. Trouve le textarea contenant le pattern
        3. Trouve l'icône square_edit.png associée
        4. Ouvre l'éditeur (clic sur square_edit)
        5. Remplace le contenu avec support des suffixes Lexpol
        6. Clique sur le bouton "Enregistrer"
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Exécuter goVariable()
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")
        await page.wait_for_timeout(3000)

        # Extraire les variables de old_pattern et new_pattern
        var_match = re.search(r'{@([^@]+)@}', old_pattern)
        if not var_match:
            print(f"   ❌ Pattern invalide: {old_pattern}")
            return False
        old_var = var_match.group(1)

        new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
        if not new_var_match:
            print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
            return False
        new_var = new_var_match.group(1)

        # Pattern de recherche : {@variable@ (sans } pour capturer les suffixes)
        old_pattern_search = f'{{@{old_var}@'
        old_pattern_lettres_search = f'{{@{old_var}_en_lettres@'

        # Chercher le textarea contenant les patterns DANS LE CONTENEUR SPÉCIFIQUE
        print(f"   🔍 Recherche du textarea dans #{param1}...")
        search_js = create_textarea_search_js(param1, old_pattern_search, old_pattern_lettres_search, 'textarea')
        textarea_id = await page.evaluate(search_js)

        if not textarea_id:
            print(f"   ❌ Textarea non trouvé")
            return False

        print(f"   ✅ Textarea: #{textarea_id}")

        # Récupérer le textarea et lire la valeur AVANT d'ouvrir
        textarea = await page.query_selector(f'textarea[id="{textarea_id}"]')
        if not textarea:
            print(f"   ❌ Textarea inaccessible")
            return False

        old_value = await textarea.input_value()

        # Appliquer les remplacements en préservant les suffixes
        new_value, total_count = replace_variable_with_suffixes(old_value, old_var, new_var)

        if total_count == 0:
            print(f"   ⚠️  Aucun remplacement nécessaire (patterns non trouvés)")
            return False

        print(f"   🔄 {total_count} remplacement(s) effectué(s)")

        # Trouver et cliquer sur square_edit pour activer l'éditeur
        print(f"   🔍 Recherche de l'icône square_edit...")
        clicked = await page.evaluate(f'''() => {{
            const ta = document.getElementById('{textarea_id}');
            if (!ta) return false;
            const tr = ta.closest('tr');
            if (!tr) return false;
            const img = tr.querySelector('img[src*="square_edit.png"]');
            if (!img) return false;
            img.click();
            return true;
        }}''')

        if not clicked:
            print(f"   ❌ square_edit non trouvé")
            return False

        # OUVRIR l'éditeur
        print(f"   👆 OUVRIR l'éditeur (clic sur square_edit)...")
        await page.wait_for_timeout(500)

        # Vider et remplir le textarea avec le pattern standard
        await fill_textarea_with_clear(textarea, new_value)
        print(f"   ✅ Contenu remplacé")

        # Chercher et cliquer sur le bouton "Enregistrer"
        print(f"   💾 Recherche du bouton Enregistrer...")

        # Dériver l'ID du bouton "Enregistrer" depuis l'ID du textarea
        # Ex: libelle_dossier_edit_txt -> libelle_dossier_save
        save_button_id = textarea_id.replace('_edit_txt', '_save')

        save_btn = await page.query_selector(f'#{save_button_id}')

        if save_btn:
            print(f"   👆 Clic sur le bouton Enregistrer (#{save_button_id})...")
            await save_btn.click()
            await page.wait_for_timeout(2000)
            print(f"   ✅ Enregistré!")
            return True
        else:
            print(f"   ❌ Bouton Enregistrer non trouvé (#{save_button_id})")
            return False


class IntituleStrategy(ReplacementStrategy):
    """
    Stratégie pour les éléments de type Intitulé

    PHILOSOPHIE:
    - Interface Lexpol: Affichage en lecture seule de l'intitulé de l'élément
    - Activation: Clic sur bouton "Modifier l'intitulé" ouvre l'éditeur Summernote
    - Édition: Éditeur WYSIWYG Summernote pour éditer l'intitulé
    - Sauvegarde: Clic sur bouton "Enregistrer" (pas de blur auto)

    IMPLÉMENTATION:
    - Cherche le bouton via attribut idelement (extrait du param1)
    - Clique sur "Modifier l'intitulé" pour afficher l'éditeur
    - Identifie le textarea Summernote par convention de nommage (intitule_element_{idelement}_edit_txt)
    - Remplace via API Summernote.code() avec regex pour préserver les suffixes
    - Clique sur bouton "Enregistrer" pour sauvegarder

    PARTICULARITÉS:
    - Utilise des boutons avec attribut idelement (pas d'ID unique)
    - Textarea Summernote avec nom prévisible basé sur idelement
    - Pas de blur auto, nécessite clic sur bouton "Enregistrer"

    UTILISÉ POUR: Intitulé des éléments
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les éléments contenant 'Intitulé'"""
        return "Intitulé" in occurrence_text

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence de type Intitulé

        Process:
        1. Exécute goVariable() pour afficher la section
        2. Clique sur le bouton "Modifier l'intitulé"
        3. Fait le remplacement dans l'éditeur Summernote
        4. Clique sur "Enregistrer"
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Exécuter goVariable()
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")
        await page.wait_for_timeout(3000)

        # Extraire les variables
        old_var_match = re.search(r'{@([^@]+)@}', old_pattern)
        if not old_var_match:
            print(f"   ❌ Pattern invalide: {old_pattern}")
            return False

        old_var = old_var_match.group(1)

        new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
        if not new_var_match:
            print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
            return False

        new_var = new_var_match.group(1)

        # Extraire l'idelement depuis param1 (ex: "elementIntituleChamp_4284865")
        element_match = re.search(r'_(\d+)$', param1)
        if not element_match:
            print(f"   ❌ Impossible d'extraire idelement de {param1}")
            return False

        idelement = element_match.group(1)

        # Chercher le bouton "Modifier l'intitulé"
        print(f"   🔍 Recherche du bouton Modifier l'intitulé...")
        modify_btn = await page.query_selector(f'button.elementIntituleModifier[idelement="{idelement}"]')

        if not modify_btn:
            print(f"   ❌ Bouton 'Modifier l'intitulé' non trouvé pour idelement={idelement}")
            return False

        # Cliquer sur "Modifier l'intitulé"
        print(f"   👆 Clic sur 'Modifier l'intitulé'...")
        await modify_btn.click()
        await page.wait_for_timeout(1000)

        # Trouver le textarea Summernote (id: intitule_element_XXXXX_edit_txt)
        textarea_id = f"intitule_element_{idelement}_edit_txt"
        print(f"   🔍 Textarea Summernote: #{textarea_id}")

        # Faire le remplacement dans Summernote via l'API Summernote
        print(f"   ✏️  Remplacement via API Summernote...")
        result = await page.evaluate(f'''() => {{
            const ta = document.getElementById('{textarea_id}');
            if (!ta) return {{ success: false, count: 0, error: 'Textarea not found' }};

            // Vérifier jQuery
            if (typeof $ === 'undefined') {{
                return {{ success: false, count: 0, error: 'jQuery not available' }};
            }}

            // Vérifier Summernote
            if (typeof $.fn.summernote === 'undefined') {{
                return {{ success: false, count: 0, error: 'Summernote not available' }};
            }}

            // Vérifier si Summernote est initialisé sur cet élément
            const $elem = $('#{textarea_id}');
            if (!$elem.data('summernote')) {{
                return {{ success: false, count: 0, error: 'Summernote not initialized on element' }};
            }}

            // Obtenir le contenu actuel via l'API Summernote
            let currentContent = $elem.summernote('code');

            // Les variables à remplacer
            const oldVar = '{old_var}';
            const newVar = '{new_var}';

            // Compter et remplacer avec replaceAll (simple string replacement, pas de regex)
            let newContent = currentContent;
            let totalCount = 0;

            // Pattern 1: {{@old_var@}}
            const pattern1 = '{{@' + oldVar + '@}}';
            const replacement1 = '{{@' + newVar + '@}}';
            const count1 = (currentContent.split(pattern1).length - 1);
            if (count1 > 0) {{
                newContent = newContent.replaceAll(pattern1, replacement1);
                totalCount += count1;
            }}

            // Pattern 2: {{@old_var_en_lettres@}}
            const pattern2 = '{{@' + oldVar + '_en_lettres@}}';
            const replacement2 = '{{@' + newVar + '_en_lettres@}}';
            const count2 = (newContent.split(pattern2).length - 1);
            if (count2 > 0) {{
                newContent = newContent.replaceAll(pattern2, replacement2);
                totalCount += count2;
            }}

            if (totalCount > 0) {{
                // Mettre à jour via l'API Summernote
                $elem.summernote('code', newContent);
            }}

            return {{ success: true, count: totalCount }};
        }}''')

        if not result.get('success') or result.get('count', 0) == 0:
            error_msg = result.get('error', 'Unknown error')
            print(f"   ⚠️  Aucun remplacement nécessaire ({error_msg})")
            return False

        print(f"   🔄 {result['count']} remplacement(s) effectué(s)")

        # Cliquer sur "Enregistrer"
        print(f"   💾 Enregistrement...")
        save_btn = await page.query_selector(f'button.intitule_element_save[idelement="{idelement}"]')

        if not save_btn:
            print(f"   ❌ Bouton 'Enregistrer' non trouvé")
            return False

        await save_btn.click()
        await page.wait_for_timeout(1000)

        print(f"   ✅ Remplacement terminé")
        return True


class VariableFieldStrategy(ReplacementStrategy):
    """
    Stratégie pour les occurrences dans les champs de variables du dossier

    PHILOSOPHIE:
    - Interface Lexpol: Variable du dossier avec valeur calculée ou valeur par défaut
    - Activation: Clic sur div.variableLecture pour activer l'édition (appelle activeModifVariable)
    - Édition: Textarea devient visible (était caché dans p.variableEdit)
    - Sauvegarde: Auto-save via blur

    IMPLÉMENTATION:
    - Extrait l'ID de la variable depuis le texte de l'occurrence
    - Trouve le textarea par son ID (= nom de la variable)
    - Trouve le data-id depuis le textarea pour appeler activeModifVariable
    - Active l'édition via activeModifVariable(id, false)
    - Remplace avec pattern Ctrl+A + Backspace + fill()
    - Déclenche blur pour sauvegarder

    STRUCTURE HTML:
    - <div class="variableLecture" onclick="activeModifVariable(id, false)">contenu</div>
    - <p class="variableEdit" style="display:none"><textarea id="nom.variable">contenu</textarea></p>

    UTILISÉ POUR: Variable du dossier (valeur calculée, valeur par défaut, etc.)
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les éléments 'Variable du dossier'"""
        # Utiliser .+ pour gérer les noms avec parenthèses (ex: "Libellé (association)")
        return bool(re.search(r'Variable du dossier \((.+)\)', occurrence_text))

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence de type 'Variable du dossier'

        Process:
        1. Exécute goVariable() pour afficher la section
        2. Extrait le nom de la variable depuis le texte de l'occurrence
        3. Trouve le textarea directement par son ID (= nom de la variable)
        4. Récupère le data-id du textarea
        5. Active l'édition via activeModifVariable(id, false)
        6. Remplace le contenu avec support des suffixes
        7. Sauvegarde via blur
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire le nom de la variable depuis le texte de l'occurrence
        # Ex: "Variable du dossier (global.auPresidentAPF)" → "global.auPresidentAPF"
        # Utiliser .+ au lieu de [^)]+ pour gérer les noms avec parenthèses (ex: "Libellé (association)")
        var_name_match = re.search(r'Variable du dossier \((.+)\)', occurrence['text'])
        if not var_name_match:
            print("   ❌ Impossible d'extraire le nom de la variable")
            return False

        textarea_id = var_name_match.group(1)
        print(f"   🔍 Textarea ID extrait du texte: {textarea_id}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Exécuter goVariable()
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")
        await page.wait_for_timeout(3000)

        # Extraire les variables
        var_match = re.search(r'{@([^@]+)@}', old_pattern)
        if not var_match:
            print(f"   ❌ Pattern invalide: {old_pattern}")
            return False

        old_var = var_match.group(1)
        new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
        if not new_var_match:
            print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
            return False
        new_var = new_var_match.group(1)

        # Vérifier que le textarea existe et récupérer son data-id
        # Échapper correctement textarea_id pour éviter les erreurs JS avec caractères spéciaux
        textarea_id_escaped = json.dumps(textarea_id)
        textarea_info = await page.evaluate(f'''() => {{
            const ta = document.getElementById({textarea_id_escaped});
            if (!ta) return null;

            const pEdit = ta.closest('p.variableEdit');
            if (!pEdit) return null;

            const dataId = pEdit.getAttribute('data-id');
            return {{
                id: ta.id,
                dataId: dataId,
                value: ta.value
            }};
        }}''')

        if not textarea_info:
            print(f"   ❌ Textarea #{textarea_id} non trouvé ou pas dans p.variableEdit")
            return False

        data_id = textarea_info['dataId']
        old_value = textarea_info['value']

        print(f"   ✅ Textarea: #{textarea_id} (data-id={data_id})")
        print(f"   📄 Contenu actuel: {old_value[:200]}...")  # DEBUG

        # Appliquer les remplacements
        new_value, total_count = replace_variable_with_suffixes(old_value, old_var, new_var)

        if total_count == 0:
            print(f"   ⚠️  Aucun remplacement nécessaire")
            return False

        print(f"   🔄 {total_count} remplacement(s) effectué(s)")

        # Activer l'édition via activeModifVariable
        print(f"   👆 Activation de l'éditeur (activeModifVariable({data_id}, false))...")
        await page.evaluate(f"activeModifVariable({data_id}, false)")
        await page.wait_for_timeout(500)

        # Récupérer le textarea maintenant qu'il est visible
        # Utiliser l'ID réel récupéré (plus sûr que textarea_id qui peut contenir des caractères spéciaux)
        real_id = textarea_info['id']
        textarea = await page.query_selector(f'textarea[id="{real_id}"]')
        if not textarea:
            print(f"   ❌ Textarea #{real_id} inaccessible après activation")
            return False

        # Remplacer le contenu
        await fill_textarea_with_clear(textarea, new_value)
        print(f"   ✅ Contenu remplacé")

        # SAUVEGARDER via blur
        print(f"   💾 Sauvegarde (blur)...")
        await textarea.evaluate('el => el.blur()')
        await page.wait_for_timeout(2000)
        print(f"   ✅ Sauvegardé!")

        return True


class VariableConditionStrategy(ReplacementStrategy):
    """
    Stratégie pour les conditions de variables du dossier

    PHILOSOPHIE:
    - Interface Lexpol: Affichage en lecture seule de la condition d'une variable
    - Activation: Clic sur square_edit.png ouvre une popup modale
    - Édition: Textarea #conditionVariableCheckbox dans la modale
    - Sauvegarde: Clic sur bouton "Enregistrer" dans la modale

    IMPLÉMENTATION:
    - Similaire à CCBFModalStrategy
    - Clique sur square_edit.png pour ouvrir la popup
    - Attend que #simplemodal-container soit visible
    - Cherche le textarea #conditionVariableCheckbox
    - Remplace avec support des suffixes
    - Clique sur le bouton de validation

    UTILISÉ POUR: Condition de la variable du dossier
    """

    async def can_handle(self, occurrence_text: str) -> bool:
        """Cette stratégie traite les éléments 'Condition de la variable du dossier'"""
        return bool(re.search(r'Condition de la variable du dossier \([^)]+\)', occurrence_text))

    async def process(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence de type 'Condition de la variable du dossier'

        Process:
        1. Exécute goVariable() pour afficher la section
        2. Trouve et clique sur square_edit.png pour ouvrir la popup
        3. Attend que la popup modale s'affiche
        4. Trouve le textarea #conditionVariableCheckbox
        5. Remplace avec support des suffixes
        6. Clique sur "Enregistrer"
        """
        print(f"   📝 {occurrence['text']}")

        # Extraire les paramètres de goVariable()
        match = re.search(r"goVariable\('([^']+)'(?:,\s*'([^']*)')?\)", occurrence['onclick'])
        if not match:
            print("   ❌ Impossible d'extraire les paramètres")
            return False

        param1 = match.group(1)
        param2 = match.group(2) if match.group(2) else ''

        # Exécuter goVariable()
        print(f"   ⚡ goVariable('{param1}', '{param2}')...")
        await page.evaluate(f"goVariable('{param1}', '{param2}')")
        await page.wait_for_timeout(2000)

        # Extraire les variables
        var_match = re.search(r'{@([^@]+)@}', old_pattern)
        if not var_match:
            print(f"   ❌ Pattern invalide: {old_pattern}")
            return False

        old_var = var_match.group(1)

        new_var_match = re.search(r'{@([^@]+)@}', new_pattern)
        if not new_var_match:
            print(f"   ❌ Nouveau pattern invalide: {new_pattern}")
            return False

        new_var = new_var_match.group(1)

        # Trouver le bouton d'édition de la condition
        # Le square_edit n'est pas dans le conteneur param1 mais dans le TR parent
        print(f"   🔍 Recherche du bouton d'édition (modifierVariableCalculee)...")

        # Extraire l'ID de la variable depuis param1
        # Ex: variableCopie2091720 → 2091720
        var_id_match = re.search(r'variableCopie(\d+)', param1)
        if not var_id_match:
            print(f"   ❌ Impossible d'extraire l'ID de la variable depuis {param1}")
            return False

        var_id = var_id_match.group(1)
        print(f"   🔍 ID de la variable: {var_id}")

        # Vérifier que le bouton modifierVariableCalculee existe
        edit_button_exists = await page.evaluate(f'''() => {{
            const container = document.getElementById('{param1}');
            if (!container) return false;

            const tr = container.closest('tr');
            if (!tr) return false;

            const img = tr.querySelector('img[onclick*="modifierVariableCalculee({var_id})"]');
            return img !== null;
        }}''')

        if not edit_button_exists:
            print(f"   ❌ Bouton modifierVariableCalculee({var_id}) non trouvé")
            return False

        # Ouvrir la popup modale en appelant modifierVariableCalculee(id)
        print(f"   👆 Ouverture de la popup modale (modifierVariableCalculee({var_id}))...")
        await page.evaluate(f'modifierVariableCalculee({var_id})')
        await page.wait_for_timeout(1500)

        # Attendre que la popup modale soit visible
        modal = await page.wait_for_selector('#simplemodal-container', timeout=5000)
        if not modal:
            print(f"   ❌ Popup modale non trouvée")
            return False

        print(f"   ✅ Popup modale ouverte")

        # Trouver le textarea #conditionVariableCheckbox
        textarea = await page.query_selector('#conditionVariableCheckbox')
        if not textarea:
            print(f"   ❌ Textarea #conditionVariableCheckbox non trouvé")
            return False

        # Lire la valeur actuelle
        current_value = await textarea.input_value()
        if not current_value:
            print(f"   ⚠️  Textarea vide")
            return False

        # Appliquer les remplacements avec support des suffixes
        new_value, count = replace_variable_with_suffixes(current_value, old_var, new_var)

        if count == 0:
            print(f"   ⚠️  Aucun remplacement nécessaire")
            # Fermer la popup sans enregistrer
            cancel_btn = await page.query_selector('#simplemodal-container .simplemodal-close')
            if cancel_btn:
                await cancel_btn.click()
                await page.wait_for_timeout(500)
            return False

        print(f"   🔄 {count} remplacement(s) effectué(s)")

        # Remplir le textarea avec la nouvelle valeur
        await fill_textarea_with_clear(textarea, new_value)
        print(f"   ✏️  Contenu modifié")

        # Chercher le bouton "Enregistrer" ou "Valider" dans la modale
        print(f"   💾 Enregistrement...")
        save_success = await page.evaluate('''() => {
            const modal = document.querySelector('#simplemodal-container');
            if (!modal) return false;

            // Chercher un bouton avec "Enregistrer" ou "Valider"
            const buttons = modal.querySelectorAll('input[type="button"], button');
            for (const btn of buttons) {
                const value = btn.value || btn.textContent || '';
                if (value.includes('Enregistrer') || value.includes('Valider')) {
                    btn.click();
                    return true;
                }
            }
            return false;
        }''')

        if not save_success:
            print(f"   ❌ Bouton Enregistrer/Valider non trouvé")
            return False

        await page.wait_for_timeout(2000)
        print(f"   ✅ Enregistré!")

        return True


class StrategyManager:
    """Gestionnaire de stratégies de remplacement"""

    def __init__(self):
        """Initialise le gestionnaire avec les stratégies disponibles"""
        self.strategies = [
            ButtonSaveStrategy(),  # Doit être avant SquareEditStrategy pour 'Intitulé du dossier'
            VariableConditionStrategy(),  # Pour "Condition de la variable du dossier"
            VariableFieldStrategy(),  # Pour "Variable du dossier"
            SquareEditStrategy(),
            ReferenceStrategy(),  # Pour "Référence(s)"
            SimpleSummernoteStrategy(),  # Pour "Attendus (Vu)"
            SummernoteStrategy(),
            IntituleStrategy(),
            CCBFModalStrategy(),
            SimpleTextareaStrategy(),
            EditableTableStrategy(),
            # Futures stratégies à ajouter ici:
            # FEditStrategy(),
            # etc.
        ]

    async def get_strategy(self, occurrence_text: str) -> ReplacementStrategy:
        """
        Trouve la stratégie appropriée pour une occurrence

        Args:
            occurrence_text: Texte de l'occurrence

        Returns:
            ReplacementStrategy ou None si aucune stratégie ne peut traiter
        """
        for strategy in self.strategies:
            if await strategy.can_handle(occurrence_text):
                return strategy
        return None

    async def process_occurrence(self, page, occurrence: dict, old_pattern: str, new_pattern: str) -> bool:
        """
        Traite une occurrence en utilisant la stratégie appropriée

        Args:
            page: Instance de page Playwright
            occurrence: Dict avec 'text' et 'onclick'
            old_pattern: Pattern à remplacer
            new_pattern: Nouveau pattern

        Returns:
            bool: True si traité avec succès, False sinon
        """
        strategy = await self.get_strategy(occurrence['text'])

        if not strategy:
            print(f"   ⏭️  IGNORÉ: {occurrence['text']} (aucune stratégie disponible)")
            return False

        return await strategy.process(page, occurrence, old_pattern, new_pattern)
