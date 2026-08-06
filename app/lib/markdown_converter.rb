# frozen_string_literal: true

require 'kramdown'
require 'kramdown/parser/gfm'

# Convertit automatiquement le Markdown en HTML pour PublipostageV3.
# Détecte les patterns Markdown courants et convertit en HTML sécurisé.
#
# Exemples :
#
# Détection :
#   MarkdownConverter.looks_like_markdown?("Texte simple")  # => false
#   MarkdownConverter.looks_like_markdown?("**gras**")      # => true
#
# Conversion :
#   MarkdownConverter.convert("**Important**")
#   # => "<p><strong>Important</strong></p>\n"
#
class MarkdownConverter
  # Emphase réellement interprétée par kramdown : gras (** ou __) ET italique
  # (* ou _). Les délimiteurs doivent être appariés sur une même ligne, coller
  # au texte (pas d'espace après l'ouvrant ni avant le fermant) et, pour les
  # underscores, ne pas être intra-mot. Ce sont les règles de « flanking » de
  # CommonMark : les reproduire évite les faux positifs sur « 3 * 4 * 5 »,
  # « mon_fichier_test.pdf » ou une URL contenant des underscores.
  #
  # Reste volontairement hors de portée : « x = 2*y*f » est détecté, car
  # kramdown y voit bel et bien de l'italique. L'ambiguïté est dans la syntaxe
  # Markdown elle-même, aucune détection ne peut la lever.
  EMPHASIS = /
    (?<ast>\*{1,2}) (?=\S) [^\n]*? \S \k<ast>
    |
    (?<![[:alnum:]_]) (?<und>_{1,2}) (?=\S) [^\n]*? \S \k<und> (?![[:alnum:]_])
  /x

  # Autres blocs Markdown : liens, titres, listes, citations
  BLOCK = /\[.+?\]\(.+?\)|(?:^|\n)#+\s|(?:^|\n)[*-]\s|(?:^|\n)>\s/m

  MARKDOWN = /#{EMPHASIS}|#{BLOCK}/

  # Détecte si un texte contient probablement du Markdown
  # Reconnaît : gras (** ou __), italique (* ou _), liens [...](...)
  # titres (#), listes (* ou -), citations (>)
  def self.looks_like_markdown?(text)
    return false unless text.is_a?(String)
    return false if text.blank?

    text.match?(MARKDOWN)
  end

  # Convertit le Markdown en HTML sécurisé
  # Utilise GitHub Flavored Markdown (tables, strikethrough, etc.)
  def self.convert(text)
    return text unless text.is_a?(String)
    return text if text.blank?

    # S'assurer que les titres (#, ##, ###...) sont précédés d'une ligne vide
    # pour que Kramdown les traite comme des blocs séparés et non comme du contenu
    # imbriqué dans une liste précédente (ce qui génère <h3> dans <li>, interdit par Sablon)
    prepared = text.gsub(/(\S[^\n]*)\n(#+\s)/, "\\1\n\n\\2")

    html = Kramdown::Document.new(
      prepared,
      input: 'GFM',                # GitHub Flavored Markdown
      hard_wrap: true,             # Convertit les line breaks en <br>
      syntax_highlighter: nil,     # Désactive highlighting (sécurité)
      html_to_native: true         # Convertit HTML existant en Markdown d'abord
    ).to_html

    # Sanitize pour sécurité (garde seulement les tags de base)
    sanitize_html(html)
  end

  # Sanitize HTML pour éviter XSS
  # Autorise uniquement les tags de formatage de base
  def self.sanitize_html(html)
    ActionController::Base.helpers.sanitize(
      html,
      tags: %w[p br strong em b i ul ol li a h1 h2 h3 h4 h5 h6 blockquote code pre hr],
      attributes: %w[href]
    )
  end
end
