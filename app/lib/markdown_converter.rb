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
  # Détecte si un texte contient probablement du Markdown
  # Reconnaît : gras (**), italique (__), liens [...](...)
  # titres (#), listes (* ou -), citations (>)
  def self.looks_like_markdown?(text)
    return false unless text.is_a?(String)
    return false if text.blank?

    # Patterns Markdown courants
    # /m permet au regex de fonctionner sur plusieurs lignes
    text.match?(/(\*\*|__|\[.+?\]\(.+?\)|(?:^|\n)#+\s|(?:^|\n)\*\s|(?:^|\n)-\s|(?:^|\n)>\s)/m)
  end

  # Convertit le Markdown en HTML sécurisé
  # Utilise GitHub Flavored Markdown (tables, strikethrough, etc.)
  def self.convert(text)
    return text unless text.is_a?(String)
    return text if text.blank?

    html = Kramdown::Document.new(
      text,
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
