#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'rubyXL'
require 'csv'

class LotissementsConverter
  INPUT_FILE = "Répertoire des lotissements et groupes d'habitation 1.xlsx"
  OUTPUT_FILE = 'lotissements_consolidated.csv'

  def initialize
    @workbook = RubyXL::Parser.parse(INPUT_FILE)
    @headers = nil
    @all_rows = []
  end

  def convert
    puts "Lecture du fichier #{INPUT_FILE}..."

    extract_headers_from_first_sheet
    process_all_sheets
    write_csv

    puts "Fichier CSV généré : #{OUTPUT_FILE}"
    puts "Total des lignes de données : #{@all_rows.size}"
  end

  private

  def extract_headers_from_first_sheet
    first_sheet = @workbook.worksheets.first
    return if first_sheet.nil?

    @headers = extract_row_values(first_sheet, 0)
    puts "En-têtes extraites : #{@headers.join(', ')}"
  end

  def process_all_sheets
    @workbook.worksheets.each_with_index do |sheet, index|
      puts "Traitement de la feuille #{index + 1}/#{@workbook.worksheets.size} : #{sheet.sheet_name}"

      # Pour la première feuille, on commence à la ligne 1 (ignore l'en-tête)
      # Pour les autres feuilles, on commence aussi à la ligne 1 (ignore leur en-tête)
      start_row = 1

      process_sheet_data(sheet, start_row)
    end
  end

  def process_sheet_data(sheet, start_row)
    return if sheet[start_row].nil?

    row_index = start_row
    while sheet[row_index]&.cells&.any? { |cell| !cell&.value.nil? }
      row_values = extract_row_values(sheet, row_index)

      # Ignore les lignes vides
      @all_rows << row_values unless row_values.all?(&:nil?) || row_values.all? { |v| v.to_s.strip.empty? }

      row_index += 1
    end
  end

  def extract_row_values(sheet, row_index)
    return [] if sheet[row_index].nil?

    # Extraire les valeurs jusqu'au nombre de colonnes des en-têtes
    max_cols = @headers&.size || sheet[row_index].cells.size

    (0...max_cols).map do |col_index|
      cell = sheet[row_index]&.cells&.[](col_index)
      cell&.value&.to_s&.strip
    end
  end

  def write_csv
    CSV.open(OUTPUT_FILE, 'w', encoding: 'UTF-8') do |csv|
      # Écrire les en-têtes
      csv << @headers if @headers

      # Écrire toutes les données
      @all_rows.each do |row|
        csv << row
      end
    end
  end
end

# Exécution du script
if __FILE__ == $PROGRAM_NAME
  begin
    converter = LotissementsConverter.new
    converter.convert
  rescue StandardError => e
    puts "Erreur : #{e.message}"
    puts e.backtrace
    exit 1
  end
end
