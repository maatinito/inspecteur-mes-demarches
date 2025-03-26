# frozen_string_literal: true

require 'nokogiri'
require 'csv'

if ARGV.empty?
  puts "Usage: ruby #{__FILE__} <path_to_document.xml>"
  exit 1
end

xml_file = ARGV[0]

class WordSaxParser < Nokogiri::XML::SAX::Document
  attr_reader :hierarchy_rows, :codes_rows

  def initialize(lppr = nil)
    super()
    @lppr = lppr
    @hierarchy_rows = [] # Chaque ligne : [id, title, level, parent_id, descriptif]
    @codes_rows = [] # Chaque ligne : [code, tarif, plv, chapter_id]

    # Gestion des titres
    @title_id_counter = 0
    @title_stack = {} # Pour mémoriser le dernier titre par niveau
    @current_chapter_id = nil

    # Gestion des paragraphes
    @inside_paragraph = false
    @current_paragraph_text = String.new
    @current_paragraph_is_title = false
    @current_title_level = nil

    # Gestion des éléments de texte (w:t)
    @current_element = nil

    # Gestion des cellules (pour les tableaux)
    @inside_cell = false
    @current_cell_text = String.new

    # Gestion des tableaux
    @inside_table = false
    @table_is_interesting = false
    @inside_row = false
    @current_row_index = 0
    @current_row_cells = []
  end

  def start_element(name, attrs = [])
    attr_hash = attrs.to_h

    case name
    when 'w:p'
      @inside_paragraph = true
      @current_paragraph_text = String.new
      @current_paragraph_is_title = false
    when 'w:pStyle'
      # Un style dont la valeur est uniquement composé de "1" (ex: "1", "11", ...) indique un titre.
      if attr_hash['w:val']&.match?(/\A1+\z/)
        @current_title_level = attr_hash['w:val'].length
        @current_paragraph_is_title = true
      end
    when 'w:t'
      @current_element = 'w:t'
    when 'w:tbl'
      @inside_table = true
      @table_is_interesting = false
      @current_row_index = 0
    when 'w:tr'
      if @inside_table
        @inside_row = true
        @current_row_cells = []
      end
    when 'w:tc'
      if @inside_row
        @inside_cell = true
        @current_cell_text = []
      end
    end
  end

  def characters(string)
    # On ajoute le texte uniquement si l'élément courant est w:t.
    return unless @current_element == 'w:t' && @inside_paragraph

    @current_paragraph_text << string
  end

  def end_element(name)
    case name
    when 'w:t'
      @current_element = nil
    when 'w:p'
      if @inside_paragraph
        if @current_paragraph_is_title
          @title_id_counter += 1
          title_id = @title_id_counter
          title_text = @current_paragraph_text.strip
          level = @current_title_level
          parent_id = nil
          (level - 1).downto(1) do |lvl|
            if @title_stack[lvl]
              parent_id = @title_stack[lvl]
              break
            end
          end
          @title_stack[level] = title_id
          # On ajoute la ligne du titre avec un descriptif initial vide.
          @hierarchy_rows << [title_id, title_text, level, parent_id, String.new]
          # On initialise le chapitre courant pour l'accumulation du descriptif.
          @current_chapter_id = title_id
        elsif !@inside_table && @current_chapter_id
          # Pour un paragraphe non-titre, si l'on est dans un contexte de chapitre (et hors d'un tableau),
          # on ajoute le texte au descriptif du chapitre.
          @hierarchy_rows.last[4] << "<br>#{@current_paragraph_text.strip.gsub(/[\r\n]+/, '<br>')}"
          # Si un titre est détecté, on finalise le descriptif du chapitre précédent (s'il existe).
        end
        @current_cell_text << @current_paragraph_text if @inside_cell
        @inside_paragraph = false
        @current_paragraph_text = String.new
        @current_paragraph_is_title = false
        @current_title_level = nil
      end
    when 'w:tc'
      if @inside_cell
        # On ajoute le texte de la cellule (seulement ce qui provient de w:t)
        @current_row_cells << @current_cell_text
        @inside_cell = false
      end
    when 'w:tr'
      if @inside_row
        if @current_row_index.zero?
          # La première ligne est l'entête : on vérifie si la première cellule contient "code" ou "codes" (sans tenir compte de la casse)
          first_cell_text = @current_row_cells[0]&.first || ''
          @table_is_interesting = (first_cell_text =~ /codes?/i)
        elsif @table_is_interesting && !(@current_row_cells[0]&.first || '').empty?
          # Pour les lignes suivantes, on ne traite que celles dont la première cellule n'est pas vide.
          code = @current_row_cells[0]&.first
          libelle = @current_row_cells[1]&.first || ''
          contexte = @current_row_cells[1]&.drop(1)&.join('<br>') || ''
          tarif = @current_row_cells[2]&.first&.gsub(' ', '') || ''
          plv = @current_row_cells[3]&.first&.gsub(' ', '') || ''
          chapter_id = @current_chapter_id || ''
          tarif_lppr = @lppr[code]
          tarif_lppr_present = @lppr.key?(code)
          @codes_rows << [code, tarif, plv, tarif_lppr, tarif_lppr_present, chapter_id, libelle, contexte]
          # On suppose ici un mapping fixe : cellule 0 = Code, cellule 2 = Tarif, cellule 3 = PLV.
        end
        @current_row_index += 1
        @inside_row = false
      end
    when 'w:tbl'
      @inside_table = false
      @table_is_interesting = false
    end
  end
end

# Exécution du parsing et export CSV

fichier = 'lppr officielle.csv'

lppr = {}

CSV.foreach(fichier, col_sep: ';', headers: true) do |row|
  code = row[0]
  tarif = row[1]&.delete(' ') # Supprime les espaces éventuels

  lppr[code] = tarif unless code.nil? || tarif.nil?
end

parser = WordSaxParser.new(lppr)
sax_parser = Nokogiri::XML::SAX::Parser.new(parser)

File.open(xml_file) do |f|
  sax_parser.parse(f)
end

CSV.open('hierarchy.csv', 'w', col_sep: ',') do |csv|
  csv << %w[id title level parent_id descriptif]
  parser.hierarchy_rows.each { |row| csv << row }
end

CSV.open('codes.csv', 'w', col_sep: ',') do |csv|
  csv << ['code', 'tarif', 'plv', 'tarif lppr', 'tarif lppr present', 'chapter_id', 'libellé', 'contexte']
  parser.codes_rows.each { |row| csv << row }
end

puts "Parsing terminé : #{parser.hierarchy_rows.size} titres et #{parser.codes_rows.size} lignes de codes extraits."
