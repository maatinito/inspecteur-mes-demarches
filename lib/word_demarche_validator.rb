# frozen_string_literal: true

require 'docx'
require 'nokogiri'

# Si exécuté hors de Rails, charger l'environnement Rails
require File.expand_path('../config/environment', __dir__) unless defined?(Rails)

class WordDemarcheValidator
  def initialize(doc_path, demarche_number)
    @doc_path = doc_path
    @demarche_number = demarche_number
    @word_fields = Set.new
    @table_fields = {}
    @demarche_fields = Set.new
    @demarche_repetition_fields = {}
  end

  def validate
    puts "Analyse du document: #{@doc_path}"
    puts "Démarche n°#{@demarche_number}"
    puts '=' * 60

    analyze_word_document
    fetch_demarche_definition
    compare_fields

    display_report
  end

  def list_demarche_fields
    puts "Récupération des champs de la démarche n°#{@demarche_number}..."
    puts '=' * 60

    fetch_demarche_definition

    puts "\n📋 STRUCTURE DES CHAMPS DE LA DÉMARCHE #{@demarche_number}"
    puts '=' * 60

    if @demarche_fields.any? || @demarche_repetition_fields.any?
      all_fields = build_demarche_fields_structure
      display_fields_structure(all_fields)
      display_demarche_summary
    else
      puts 'Aucun champ trouvé pour cette démarche.'
    end
  end

  def build_demarche_fields_structure
    all_fields = @demarche_fields.to_a.sort.map do |field|
      { name: field, type: :simple }
    end

    @demarche_repetition_fields.keys.sort.each do |repetition_name|
      all_fields << {
        name: repetition_name,
        type: :repetition,
        sub_fields: @demarche_repetition_fields[repetition_name].to_a.sort
      }
    end

    all_fields.sort_by { |f| f[:name] }
  end

  def display_fields_structure(all_fields)
    all_fields.each do |field|
      if field[:type] == :simple
        puts "- #{field[:name]}"
      else
        puts "- #{field[:name]} (bloc répétable):"
        field[:sub_fields].each do |sub_field|
          puts "  - #{sub_field}"
        end
      end
    end
  end

  def display_demarche_summary
    puts "\n#{'=' * 60}"
    puts 'RÉSUMÉ:'
    puts "- #{@demarche_fields.size} champ(s) simple(s)"
    puts "- #{@demarche_repetition_fields.size} bloc(s) répétable(s)"
    total_sub_fields = @demarche_repetition_fields.values.map(&:size).sum
    puts "- #{total_sub_fields} sous-champ(s) dans les blocs répétables"
  end

  def list_word_fields
    puts "Analyse du document: #{@doc_path}"
    puts '=' * 60

    analyze_word_document

    puts "\n📄 VARIABLES TROUVÉES DANS LE DOCUMENT WORD"
    puts '=' * 60

    if @word_fields.any? || @table_fields.any?
      all_fields = build_word_fields_structure
      display_word_fields(all_fields)
      display_word_summary
    else
      puts 'Aucune variable trouvée dans le document.'
    end
  end

  def build_word_fields_structure
    all_fields = @word_fields.to_a.sort.map do |field|
      { name: field, type: :simple }
    end

    @table_fields.keys.sort.each do |table_name|
      all_fields << {
        name: table_name,
        type: :table,
        sub_fields: @table_fields[table_name].to_a.sort
      }
    end

    all_fields.sort_by { |f| f[:name] }
  end

  def display_word_fields(all_fields)
    all_fields.each do |field|
      if field[:type] == :simple
        puts "- #{field[:name]}"
      else
        puts "- #{field[:name]} (table):"
        field[:sub_fields].each do |sub_field|
          puts "  - #{sub_field}"
        end
      end
    end
  end

  def display_word_summary
    puts "\n#{'=' * 60}"
    puts 'RÉSUMÉ:'
    puts "- #{@word_fields.size} variable(s) simple(s)"
    puts "- #{@table_fields.size} table(s)"
    total_sub_fields = @table_fields.values.map(&:size).sum
    puts "- #{total_sub_fields} variable(s) dans les tables"
  end

  private

  def analyze_word_document
    doc = Docx::Document.open(@doc_path)

    extract_from_paragraphs(doc)
    extract_from_tables(doc)
    extract_from_headers_footers(doc)
  end

  def extract_from_paragraphs(doc)
    doc.paragraphs.each do |paragraph|
      extract_from_paragraph(paragraph)
    end
  end

  def extract_from_tables(doc)
    doc.tables.each do |table|
      # Récupérer le nom de la table depuis la légende
      caption = table.node.xpath('w:tblPr/w:tblCaption/@w:val').text
      if caption.present?
        @table_fields[caption] = Set.new
        current_table = @table_fields[caption]
      else
        current_table = nil
      end

      table.rows.each_with_index do |row, row_index|
        # Pour les tables avec caption, la dernière ligne contient les variables du template
        is_template_row = caption.present? && row_index == table.rows.count - 1

        row.cells.each do |cell|
          cell.paragraphs.each do |paragraph|
            if current_table && is_template_row
              # Extraire les champs de la ligne template
              extract_fields_to_set(paragraph, current_table)
            else
              # Extraire normalement pour les autres lignes
              extract_from_paragraph(paragraph)
            end
          end
        end
      end
    end
  end

  def extract_from_headers_footers(doc)
    doc.doc.xpath('//w:hdr | //w:ftr').each do |header_footer|
      header_footer.xpath('.//w:p').each do |p_node|
        paragraph = Docx::Elements::Paragraph.new(p_node, doc)
        extract_from_paragraph(paragraph)
      end
    end
  end

  def extract_from_paragraph(paragraph)
    extract_fields_to_set(paragraph, @word_fields)
  end

  def extract_fields_to_set(paragraph, target_set)
    # Placeholders simples --variable--
    paragraph.each_text_run do |tr|
      text = tr.text

      text.scan(/--([^-]+)--/).each do |match|
        target_set << match[0]
      end

      # Extraire les champs MERGEFIELD selon la même logique que publipostage_v2
      extract_mergefield_from_text_run(tr, target_set)
    end

    # Instructions MERGEFIELD dans w:fldSimple
    extract_mergefield_from_field_simple(paragraph, target_set)
  end

  def extract_mergefield_from_text_run(text_run, target_set)
    # Chercher les instructions MERGEFIELD dans w:instrText, comme dans publipostage_v2
    nodeset = text_run.xpath("w:instrText[starts-with(., ' MERGEFIELD')]")
    return unless nodeset.size.positive?

    field_name = extract_field_name_from_instruction(nodeset.text)
    target_set << field_name if field_name
  end

  def extract_mergefield_from_field_simple(paragraph, target_set)
    # Extraire les champs des w:fldSimple, comme dans publipostage_v2
    paragraph.xpath('w:fldSimple').each do |node|
      instr = node.attribute('instr')
      next unless instr

      field_name = extract_field_name_from_instruction(instr.text)
      target_set << field_name if field_name
    end
  end

  def extract_field_name_from_instruction(instr_text)
    return nil unless instr_text.include?('MERGEFIELD')

    # Utiliser la même regex que publipostage_v2
    match = instr_text.match(/MERGEFIELD\s+(?:"([^"]+)"|([^" ]+))/)
    return nil unless match

    match[1].presence || match[2]
  end

  def extract_field_name(instr_text)
    # Méthode de compatibilité, rediriger vers la nouvelle méthode
    extract_field_name_from_instruction(instr_text)
  end

  def fetch_demarche_definition
    result = MesDemarches.query(
      MesDemarches::Queries::DemarcheRevision,
      variables: { demarche: @demarche_number }
    )

    raise "Erreur lors de la récupération de la démarche: #{result.errors.messages.join(', ')}" if result.errors.any?

    demarche = result.data.demarche
    raise "Démarche #{@demarche_number} non trouvée" unless demarche

    # Extraire les champs
    process_descriptors(demarche.published_revision.champ_descriptors, 'champ') if demarche.published_revision&.champ_descriptors

    # Extraire les annotations privées
    return unless demarche.published_revision&.annotation_descriptors

    process_descriptors(demarche.published_revision.annotation_descriptors, 'annotation')
  end

  def process_descriptors(descriptors, _prefix = nil)
    descriptors.each do |descriptor|
      # Ignorer les titres et explications qui ne sont pas de vrais champs
      next if descriptor.__typename == 'HeaderSectionChampDescriptor'
      next if descriptor.__typename == 'ExplicationChampDescriptor'

      field_name = descriptor.label

      if descriptor.__typename == 'RepetitionChampDescriptor'
        # C'est un champ répétable (tableau)
        @demarche_repetition_fields[field_name] = Set.new

        # Ajouter les sous-champs (en filtrant aussi les titres/explications)
        descriptor.champ_descriptors&.each do |sub_descriptor|
          next if sub_descriptor.__typename == 'HeaderSectionChampDescriptor'
          next if sub_descriptor.__typename == 'ExplicationChampDescriptor'

          @demarche_repetition_fields[field_name] << sub_descriptor.label
        end
      else
        @demarche_fields << field_name
      end
    end
  end

  def compare_fields
    @missing_in_demarche = Set.new
    @missing_table_definitions = {}
    @table_field_issues = {}

    # Vérifier les champs simples
    @word_fields.each do |field|
      @missing_in_demarche << field unless field_exists_in_demarche?(field)
    end

    # Vérifier les tables
    @table_fields.each do |table_name, table_fields|
      if @demarche_repetition_fields.key?(table_name)
        # La table existe comme champ répétable
        missing_fields = []
        table_fields.each do |field|
          missing_fields << field unless @demarche_repetition_fields[table_name].include?(field)
        end
        @table_field_issues[table_name] = missing_fields unless missing_fields.empty?
      else
        # La table n'existe pas comme champ répétable
        @missing_table_definitions[table_name] = table_fields
      end
    end
  end

  def field_exists_in_demarche?(field_name)
    # Vérifier dans les champs simples
    return true if @demarche_fields.include?(field_name)

    # Vérifier dans tous les sous-champs des répétitions
    @demarche_repetition_fields.each_value do |sub_fields|
      return true if sub_fields.include?(field_name)
    end

    false
  end

  def display_report
    display_report_header
    display_word_fields_report
    display_demarche_fields_report
    display_problems
    display_report_summary
  end

  def display_report_header
    puts "\n#{'=' * 60}"
    puts "RAPPORT D'ANALYSE"
    puts '=' * 60
  end

  def display_word_fields_report
    puts "\n📄 CHAMPS TROUVÉS DANS LE DOCUMENT WORD:"
    puts '-' * 40

    if @word_fields.empty?
      puts 'Aucun champ simple trouvé'
    else
      puts "#{@word_fields.size} champ(s) simple(s):"
      @word_fields.to_a.sort.each { |field| puts "  • #{field}" }
    end

    return unless @table_fields.any?

    puts "\n#{@table_fields.size} table(s) avec champs:"
    @table_fields.each do |table_name, fields|
      puts "  📊 Table '#{table_name}':"
      fields.to_a.sort.each { |field| puts "    • #{field}" }
    end
  end

  def display_demarche_fields_report
    puts "\n🌐 CHAMPS DÉFINIS DANS LA DÉMARCHE:"
    puts '-' * 40
    puts "#{@demarche_fields.size} champ(s) simple(s)"
    puts "#{@demarche_repetition_fields.size} champ(s) répétable(s)"
  end

  def display_problems
    puts "\n⚠️  PROBLÈMES DÉTECTÉS:"
    puts '-' * 40

    if no_problems?
      puts '✅ Aucun problème détecté - tous les champs du document correspondent à la démarche'
    else
      display_missing_fields_problems
      display_missing_table_problems
      display_table_field_issues
    end
  end

  def no_problems?
    @missing_in_demarche.empty? &&
      @missing_table_definitions.empty? &&
      @table_field_issues.empty?
  end

  def display_missing_fields_problems
    return unless @missing_in_demarche.any?

    puts "\n❌ Champs utilisés dans Word mais absents de la démarche:"
    @missing_in_demarche.to_a.sort.each do |field|
      puts "  • #{field}"
    end
  end

  def display_missing_table_problems
    return unless @missing_table_definitions.any?

    puts "\n❌ Tables définies dans Word mais absentes de la démarche:"
    @missing_table_definitions.each do |table_name, fields|
      puts "  • Table '#{table_name}' (non définie comme champ répétable)"
      puts '    Champs utilisés dans cette table:'
      fields.to_a.sort.each { |field| puts "      - #{field}" }
    end
  end

  def display_table_field_issues
    return unless @table_field_issues.any?

    puts "\n❌ Tables avec champs manquants dans la démarche:"
    @table_field_issues.each do |table_name, missing_fields|
      puts "  • Table '#{table_name}':"
      puts '    Champs manquants dans le champ répétable:'
      missing_fields.each { |field| puts "      - #{field}" }
    end
  end

  def display_report_summary
    puts "\n#{'=' * 60}"
    puts 'RÉSUMÉ:'
    total_issues = calculate_total_issues

    if total_issues.zero?
      puts '✅ Document valide - tous les champs correspondent'
    else
      puts "⚠️  #{total_issues} problème(s) détecté(s)"
      puts 'Vérifiez que tous les champs utilisés dans le document Word'
      puts "sont bien définis dans la démarche n°#{@demarche_number}"
    end
  end

  def calculate_total_issues
    @missing_in_demarche.size +
      @missing_table_definitions.values.map(&:size).sum +
      @table_field_issues.values.map(&:size).sum
  end
end

def process_single_argument(arg)
  if arg.downcase.end_with?('.docx')
    process_word_file(arg)
  elsif arg.match?(/^\d+$/)
    process_demarche_number(arg.to_i)
  else
    puts "Erreur: L'argument doit être soit un fichier .docx, soit un numéro de démarche"
    exit 1
  end
end

def process_word_file(doc_path)
  unless File.exist?(doc_path)
    puts "Erreur: Fichier '#{doc_path}' introuvable"
    exit 1
  end

  validator = WordDemarcheValidator.new(doc_path, nil)
  validator.list_word_fields
rescue StandardError => e
  handle_error(e)
end

def process_demarche_number(demarche_number)
  validator = WordDemarcheValidator.new(nil, demarche_number)
  validator.list_demarche_fields
rescue StandardError => e
  handle_error(e)
end

def process_two_arguments(doc_path, demarche_number)
  validate_docx_file(doc_path)

  validator = WordDemarcheValidator.new(doc_path, demarche_number.to_i)
  validator.validate
rescue StandardError => e
  handle_error(e)
end

def validate_docx_file(doc_path)
  unless File.exist?(doc_path)
    puts "Erreur: Fichier '#{doc_path}' introuvable"
    exit 1
  end

  return if doc_path.downcase.end_with?('.docx')

  puts 'Erreur: Le fichier doit être un .docx'
  exit 1
end

def handle_error(error)
  puts "Erreur: #{error.message}"
  puts error.backtrace if ENV['DEBUG']
  exit 1
end

def display_usage
  puts 'Usage:'
  puts "  #{__FILE__} <path_to_docx_file>                  # Liste les variables du document Word"
  puts "  #{__FILE__} <demarche_number>                    # Liste les champs de la démarche"
  puts "  #{__FILE__} <path_to_docx_file> <demarche_number> # Compare le document avec la démarche"
  puts "\nExemples:"
  puts "  ruby #{__FILE__} document.docx                   # Liste les variables de document.docx"
  puts "  ruby #{__FILE__} 3111                            # Liste les champs de la démarche 3111"
  puts "  ruby #{__FILE__} document.docx 1234              # Compare document.docx avec la démarche 1234"
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    display_usage
    exit 1
  end

  case ARGV.length
  when 1
    process_single_argument(ARGV[0])
  when 2
    process_two_arguments(ARGV[0], ARGV[1])
  else
    puts "Erreur: Nombre d'arguments invalide"
    puts "Utilisez '#{__FILE__}' sans arguments pour voir l'aide"
    exit 1
  end
end
