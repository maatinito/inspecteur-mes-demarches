# frozen_string_literal: true

require 'sablon'

# PublipostageV3 utilise la gem Sablon pour générer des documents Word.
# Cette version simplifie grandement la génération de documents en déplaçant la logique
# de répétition (tableaux) et de mise en forme (HTML) dans le template .docx lui-même.
#
# Pour les tableaux (blocs répétables) :
#   - Utilisez la syntaxe `«#each_NOM_DU_CHAMP:item»` dans la première cellule de la ligne à répéter.
#   - Utilisez `«item.NOM_DE_LA_COLONNE»` pour les valeurs.
#   - Fermez avec `«/each_NOM_DU_CHAMP»` dans la dernière cellule.
#
# Pour le texte riche :
#   - Passez du HTML dans vos données. Sablon le convertira en format Word.
#   - Exemple : '<strong>Texte en gras</strong>'
#
# Pour les images :
#   - Le support peut être ajouté via `Sablon.content(:image, 'path/to/image.png')`.
#
class PublipostageV3 < PublipostageV2
  def version
    3
  end

  # Génère le document .docx en utilisant Sablon.
  # L'intelligence est principalement dans le template, le code est donc très simple.
  def generate_docx(output_file, fields)
    template_path = VerificationService.file_manager.filepath(@template).to_s
    template = Sablon.template(template_path)

    # Sablon gère la substitution des champs, des blocs répétables (tableaux)
    # et la conversion HTML directement.
    template.render_to_file(output_file, fields)
  end

  # Pas besoin de redéfinir les autres méthodes de génération de V2 (process_table, etc.)
  # car Sablon s'en charge.
  # Nous héritons de PublipostageV2 pour réutiliser la logique de préparation des
  # données dans `champ_value`, qui transforme les blocs répétables et autres
  # types de champs complexes en une structure de données simple (Array de Hashes)
  # que Sablon peut consommer directement.
end
