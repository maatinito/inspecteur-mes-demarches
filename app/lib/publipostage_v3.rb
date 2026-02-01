# frozen_string_literal: true

require 'sablon'

# PublipostageV3 utilise la gem Sablon pour générer des documents Word.
# Cette version simplifie grandement la génération de documents en déplaçant la logique
# de répétition (tableaux) et de mise en forme (HTML) dans le template .docx lui-même.
#
# Pour les tableaux (blocs répétables) :
#   - Utilisez la syntaxe `«champ:each(item)»` ... `«champ:endEach»`
#   - Utilisez `«=item.colonne»` pour insérer les valeurs
#   - Exemple : `«participants:each(p)»«=p.nom»«participants:endEach»`
#
# Pour le texte riche :
#   - Passez du HTML dans vos données. Sablon le convertira en format Word.
#   - Exemple : '<strong>Texte en gras</strong>'
#
# Pour les images (PieceJustificativeFile) :
#   - Syntaxe : `«@fichier.image:start»[placeholder image]«@fichier.image:end»`
#   - Exemple complet :
#     `«photos:each(photo)»«@photo.image:start»[img]«@photo.image:end»«photos:endEach»`
#
# Pour les fichiers Excel/CSV (PieceJustificativeFile) :
#   - Utilisez `fichier.rows` ou `fichier.lignes` pour accéder aux lignes
#   - Exemple :
#     `«fichiers:each(f)»«f.rows:each(ligne)»«=ligne.Col1»«f.rows:endEach»«fichiers:endEach»`
#
# Pour les métadonnées (PieceJustificativeFile) :
#   - `«=fichier.nom»` ou `«=fichier.filename»` : Nom du fichier
#   - `«=fichier.taille»` ou `«=fichier.size»` : Taille formatée (ex: "1.5 MB")
#   - `«=fichier.lien»` ou `«=fichier.link»` : URL du fichier
#   - `«=fichier.type»` : Extension (ex: "jpg", "pdf", "xlsx")
#
# Pour les conditionnels :
#   - Syntaxe : `«variable:if(predicate?)»...«variable:endIf»`
#   - Exemple : `«photo.image:if(present?)»«@photo.image:start»[img]«@photo.image:end»«photo.image:endIf»`
#
class PublipostageV3 < PublipostageV2
  def version
    3
  end

  # Génère le document .docx en utilisant Sablon.
  # L'intelligence est principalement dans le template, le code est donc très simple.
  def generate_docx(output_file, fields)
    # Configure Sablon pour utiliser les styles français de Word
    configure_sablon_for_french_word

    template_path = VerificationService.file_manager.filepath(@template).to_s
    template = Sablon.template(template_path)

    # Transformation récursive du contexte :
    # 1. Transforme les clés à tous les niveaux (parameterize)
    # 2. Wrappe les tableaux de valeurs simples dans ArrayValue
    # 3. Garde les tableaux de Hash et d'objets pour les boucles Sablon
    context = normalize_context(fields)

    template.render_to_file(output_file, context)
  end

  # Pas besoin de redéfinir les autres méthodes de génération de V2 (process_table, etc.)
  # car Sablon s'en charge.
  # Nous héritons de PublipostageV2 pour réutiliser la logique de préparation des
  # données dans `champ_value`, qui transforme les blocs répétables et autres
  # types de champs complexes en une structure de données simple (Array de Hashes)
  # que Sablon peut consommer directement.

  private

  # Configure Sablon pour utiliser les styles Word français.
  # Les documents Word français utilisent des noms de styles différents :
  # - Titre1, Titre2... au lieu de Heading1, Heading2...
  # - Normal au lieu de Paragraph
  # - ListParagraph au lieu de ListBullet/ListNumber
  def configure_sablon_for_french_word
    config = Sablon::Configuration.instance
    configure_paragraph_styles(config)
    configure_heading_styles(config)
    configure_list_styles(config)
  end

  def configure_paragraph_styles(config)
    # Paragraphes : utiliser "Normal" au lieu de "Paragraph"
    # Le style "Paragraph" n'existe pas toujours et peut hériter du formatage gras
    config.register_html_tag(:p, :block,
                             ast_class: :paragraph,
                             properties: { pStyle: 'Normal' },
                             allowed_children: :_inline)
  end

  def configure_heading_styles(config)
    # Titres : utiliser "Titre1", "Titre2"... au lieu de "Heading1", "Heading2"...
    (1..6).each do |level|
      config.register_html_tag(:"h#{level}", :block,
                               ast_class: :paragraph,
                               properties: { pStyle: "Titre#{level}" },
                               allowed_children: :_inline)
    end
  end

  def configure_list_styles(config)
    # Listes : utiliser "Paragraphedeliste" (styleId du template Word français)
    config.register_html_tag(:ul, :block,
                             ast_class: :list,
                             properties: { pStyle: 'Paragraphedeliste' },
                             allowed_children: %i[ul li])

    config.register_html_tag(:ol, :block,
                             ast_class: :list,
                             properties: { pStyle: 'Paragraphedeliste' },
                             allowed_children: %i[ol li])
  end

  # Surcharge de champ_value pour retourner des objets PieceJustificativeFile
  # au lieu de parser immédiatement les fichiers Excel (comportement V1/V2).
  # Cela permet un lazy loading et un accès unifié aux images, Excel, et liens.
  #
  # IMPORTANT : Cette surcharge ne casse pas V1/V2 car elle est uniquement
  # dans PublipostageV3. V1 et V2 continuent d'utiliser excel_to_rows().
  def champ_value(champ)
    return super unless champ.respond_to?(:__typename)

    case champ.__typename
    when 'PieceJustificativeChamp'
      # V3 : Retourne un tableau d'objets PieceJustificativeFile pour lazy loading
      # (V1/V2 : appellent excel_to_rows qui retourne Array de Hash)
      champ.files.map { |file| PieceJustificativeFile.new(file) }
    else
      # Tous les autres types délèguent à PublipostageV2
      super
    end
  end

  # Surcharge pour gérer Markdown dans les colonnes ReferentielDePolynesie
  # Les colonnes Baserow peuvent contenir du Markdown qui sera automatiquement
  # converti en HTML pour Sablon.
  def expand_referentiel_de_polynesie(champ)
    result = {}
    # Valeur principale (clé vide)
    result[''] = champ.string_value || ''

    # Expansion des colonnes (clés préfixées par ".")
    if champ.respond_to?(:columns) && champ.columns
      champ.columns.each do |column|
        key = ".#{column.name}"
        value = convert_column_value(column.value)

        # Conversion automatique Markdown → HTML pour les colonnes textuelles
        if value.is_a?(String) && MarkdownConverter.looks_like_markdown?(value)
          html = MarkdownConverter.convert(value)
          result[key] = Sablon.content(:html, html)
        else
          result[key] = value.nil? ? '' : value
        end
      end
    end

    result
  end

  # Normalise récursivement le contexte pour Sablon :
  # - Transforme les clés avec parameterize (accents, espaces, etc.)
  # - Wrappe les tableaux de valeurs simples dans ArrayValue
  # - Convertit automatiquement le Markdown en HTML
  # - Garde les tableaux de Hash et d'objets tels quels
  def normalize_context(value)
    case value
    when Hash
      value.transform_keys { |k| k.parameterize(separator: '_') }
           .transform_values { |v| normalize_context(v) }
    when Array
      if simple_array?(value)
        # Tableau de valeurs simples → ArrayValue pour double usage (boucle + string)
        ArrayValue.new(value)
      else
        # Tableau de Hash ou d'objets → garder tel quel pour boucles Sablon
        value.map { |v| normalize_context(v) }
      end
    when String
      # Conversion automatique Markdown → HTML si détecté
      convert_markdown_if_detected(value)
    else
      value
    end
  end

  # Convertit en HTML si Markdown détecté, sinon retourne le texte tel quel
  def convert_markdown_if_detected(text)
    if MarkdownConverter.looks_like_markdown?(text)
      html = MarkdownConverter.convert(text)
      Sablon.content(:html, html)
    else
      text
    end
  end

  # Détermine si un tableau contient uniquement des valeurs simples
  # (pas de Hash, pas d'objets complexes comme PieceJustificativeFile)
  def simple_array?(array)
    return false if array.empty?

    array.all? { |item| simple_value?(item) }
  end

  # Détermine si une valeur est simple (String, Numeric, nil, true, false)
  def simple_value?(value)
    value.nil? || value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
  end
end
