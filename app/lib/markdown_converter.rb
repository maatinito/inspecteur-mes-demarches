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
# == Listes : paragraphes indentés, pas de liste Word
#
# Les lignes de liste ne sont PAS converties en <ul>/<ol> mais en paragraphes
# indentés dont le marqueur écrit par l'auteur est conservé tel quel. Trois
# raisons, toutes vérifiées sur le corpus des référentiels :
#
# 1. Word renumérote. Kramdown perd le numéro d'origine (« 3. » devient le
#    premier <li> d'un <ol>, sans attribut start) : un document affichait « 1. »
#    là où l'auteur avait écrit « 3. ». Les rédactions manuelles utilisent aussi
#    des marqueurs que Markdown ne connaît pas (« 1a. », « 1b. »).
# 2. Sablon aplatit les sous-listes en fratrie, mais seulement celles de même
#    tag : un <ul> dans le <li> d'un <ol> produisait des <w:p> imbriqués,
#    interdits par le schéma OpenXML — Word refusait d'ouvrir le document.
# 3. Une liste Word exige que le template déclare un w:abstractNum lié au style
#    de liste, ce que Word n'écrit que pour les styles de liste liés. Sans lui,
#    Sablon lève ArgumentError et le publipostage échoue.
#
# Le rendu en paragraphes indentés supprime les trois : aucun numPr, aucune
# dépendance à word/numbering.xml, aucune imbrication de blocs, et le texte de
# l'auteur est restitué à l'identique quelle que soit sa convention d'écriture.
# Le retrait s'appuie sur `margin-left`, converti en <w:ind> par PublipostageV3.
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

  # Marqueur de liste en tête de ligne. Volontairement plus large que Markdown :
  # les rédacteurs des référentiels écrivent « 1a. », « a) » ou « • », que
  # kramdown ne reconnaît pas. Le marqueur capturé est réaffiché tel quel.
  LIST_MARKER = /\d+[a-z]?[.)]|[a-z][.)]|[-*•–—]/
  LIST_LINE = /\A(?<indent>[ \t]*)(?<marker>#{LIST_MARKER})[ \t]+(?<text>\S.*)\z/

  # Autres blocs Markdown : liens, titres, listes, citations.
  # Les listes numérotées sont désormais détectées : sans cela une valeur
  # composée uniquement de « 1. … / 2. … » n'était pas convertie et partait
  # dans Word en un seul bloc de texte, sauts de ligne compris.
  BLOCK = /\[.+?\]\(.+?\)|(?:^|\n)#+\s|(?:^|\n)[ \t]*#{LIST_MARKER}[ \t]|(?:^|\n)>\s/m

  MARKDOWN = /#{EMPHASIS}|#{BLOCK}/

  # Retrait du premier niveau, puis incrément par niveau, en points.
  BASE_INDENT_PT = 18
  INDENT_STEP_PT = 18
  # Retrait négatif de première ligne : les lignes longues s'alignent sous le
  # texte de l'item et non sous son marqueur.
  HANGING_TWIPS = 280

  # Une tabulation vaut 4 espaces pour le calcul des niveaux d'imbrication.
  TAB_WIDTH = 4

  # Éléments de bloc à déballer dans le contenu d'un item de liste.
  BLOCK_TAGS = %w[p div h1 h2 h3 h4 h5 h6 blockquote pre ul ol li].freeze

  # Détecte si un texte contient probablement du Markdown
  # Reconnaît : gras (** ou __), italique (* ou _), liens [...](...)
  # titres (#), listes (marqueur en tête de ligne), citations (>)
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

    runs(text).map { |run| render_run(run) }.join
  end

  # Découpe le texte en suites de lignes homogènes : les lignes portant un
  # marqueur de liste d'un côté, tout le reste de l'autre. Chaque suite est
  # rendue par le moteur qui lui convient, ce qui laisse les titres, citations
  # et paragraphes ordinaires à kramdown.
  def self.runs(text)
    text.lines.map(&:chomp).slice_when { |a, b| a.match?(LIST_LINE) != b.match?(LIST_LINE) }.to_a
  end

  def self.render_run(lines)
    lines.first.match?(LIST_LINE) ? render_list(lines) : render_prose(lines)
  end

  # Rend chaque ligne de liste comme un paragraphe indenté préfixé de son
  # marqueur d'origine. Les niveaux sont déduits des largeurs d'indentation
  # présentes dans la suite : le corpus mélange les conventions (2, 3 ou 4
  # espaces, tabulations), seul leur ordre relatif a un sens.
  def self.render_list(lines)
    matches = lines.map { |line| LIST_LINE.match(line) }
    levels = indent_levels(matches.map { |m| indent_width(m[:indent]) })

    matches.each_with_index.map do |match, i|
      paragraph(match[:marker], inline_html(match[:text]), levels[i])
    end.join
  end

  def self.render_prose(lines)
    text = lines.join("\n")
    return '' if text.blank?

    flatten_html_lists(sanitize_html(kramdown_html(prepare_headings(text))))
  end

  # Une valeur peut contenir du HTML brut, que kramdown recopie tel quel. Les
  # <ul>/<ol> qui en ressortent sont ramenés à la même forme que les listes
  # Markdown : sinon ils repartiraient en listes Word, avec l'imbrication de
  # <w:p> et la dépendance à word/numbering.xml que ce module écarte.
  def self.flatten_html_lists(html)
    return html unless html.match?(/<[uo]l[\s>]/)

    doc = Nokogiri::HTML.fragment(html)
    while (list = doc.css('ul, ol').find { |node| node.ancestors('ul, ol').empty? })
      list.replace(list_paragraphs(list, 0))
    end
    doc.to_html
  end

  def self.list_paragraphs(list, level)
    ordered = list.name == 'ol'
    list.xpath('./li').each_with_index.map do |item, index|
      sublists = item.xpath('./ul | ./ol').each(&:unlink)
      marker = ordered ? "#{index + 1}." : '-'
      paragraph(marker, item_content(item), level) +
        sublists.map { |sublist| list_paragraphs(sublist, level + 1) }.join
    end.join
  end

  # Un <li> peut contenir plusieurs paragraphes : ils sont réunis en un seul,
  # séparés par des sauts de ligne, pour ne jamais imbriquer de blocs.
  def self.item_content(item)
    flatten_blocks(item.inner_html)
  end

  # Associe à chaque largeur d'indentation son rang, pour obtenir des niveaux
  # 0, 1, 2… quelle que soit l'unité d'indentation employée.
  def self.indent_levels(widths)
    ranks = widths.uniq.sort.each_with_index.to_h
    widths.map { |width| ranks[width] }
  end

  def self.indent_width(indent)
    indent.gsub("\t", ' ' * TAB_WIDTH).length
  end

  def self.paragraph(marker, content, level)
    indent = BASE_INDENT_PT + (level * INDENT_STEP_PT)
    marker = CGI.escapeHTML(marker.to_s)
    prefix = marker.empty? ? '' : "#{marker} "
    %(<p style="margin-left: #{indent}pt">#{prefix}#{content}</p>)
  end

  # Convertit le contenu d'un item : uniquement les marques inline (gras,
  # italique, liens), sans les blocs ajoutés par kramdown.
  def self.inline_html(text)
    flatten_blocks(sanitize_html(kramdown_html(text)))
  end

  # Déballe tout élément de bloc en son contenu, séparé par des sauts de ligne.
  # Le contenu d'un paragraphe de liste doit rester strictement inline : un bloc
  # imbriqué reproduirait les <w:p> dans <w:p> que Word refuse d'ouvrir.
  def self.flatten_blocks(html)
    fragment = Nokogiri::HTML.fragment(html)
    while (block = fragment.css(BLOCK_TAGS.join(', ')).first)
      block.replace("#{block.inner_html}<br>")
    end
    # Nokogiri réindente en sérialisant : l'espace qui suit un saut de ligne
    # deviendrait un retrait visible dans Word.
    fragment.to_html.strip.sub(%r{(<br\s*/?>)+\z}, '').gsub(%r{(<br\s*/?>)\s+}, '\1')
  end

  def self.kramdown_html(text)
    Kramdown::Document.new(
      text,
      input: 'GFM',                # GitHub Flavored Markdown
      hard_wrap: true,             # Convertit les line breaks en <br>
      syntax_highlighter: nil,     # Désactive highlighting (sécurité)
      html_to_native: true         # Convertit HTML existant en Markdown d'abord
    ).to_html
  end

  # S'assure que les titres (#, ##, ###...) sont précédés d'une ligne vide
  # pour que Kramdown les traite comme des blocs séparés et non comme du contenu
  # imbriqué dans le paragraphe précédent.
  def self.prepare_headings(text)
    text.gsub(/(\S[^\n]*)\n(#+\s)/, "\\1\n\n\\2")
  end

  # Sanitize HTML pour éviter XSS
  # Autorise uniquement les tags de formatage de base
  #
  # Note : `style` n'est pas autorisé ici. Le retrait des paragraphes de liste
  # est posé par `paragraph` APRÈS ce filtrage, sur du contenu déjà assaini.
  def self.sanitize_html(html)
    ActionController::Base.helpers.sanitize(
      html,
      tags: %w[p br strong em b i ul ol li a h1 h2 h3 h4 h5 h6 blockquote code pre hr],
      attributes: %w[href]
    )
  end
end
