# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'

class ExcelCheck < FieldChecker
  # Constants to define in subclasses
  #
  # ----- columns to look for in the excel
  #
  # COLUMNS = {
  #   nom: /Nom de famille/,
  #   nom_marital: /Nom marital/,
  #   prenoms: /Prénom/
  # }
  #
  # ----- checks to perform on each lines
  # CHECKS = %i[format_dn nom prenoms empty_columns].freeze
  #
  # ----- if calling empty_columnsin CHECKS, list of columns that must be filled
  # REQUIRED_COLUMNS = %i[heure_avant_convention brut_mensuel_moyen heures_a_realiser dmo].freeze

  def initialize(params)
    super(params)
    @cps = Cps::API.new
  end

  def version
    super + 7
  end

  def required_fields
    super + %i[
      champ
      message_champ_non_renseigne
      message_colonnes_manquantes
      message_date_de_naissance
      message_dn
      message_format_date_de_naissance
      message_format_dn
      message_nom_invalide
      message_prenom_invalide
      message_type_de_fichier
    ]
  end

  def check(dossier)
    champs = dossier_fields(dossier, @params[:champ])
    return if champs.blank?

    champ = champs.first
    champ_files = nil
    begin
      champ_files = champ.files
    rescue GraphQL::Client::InvariantError
      champ_files = [champ.file]
    end
    add_message(champ.label, '', @params[:message_champ_non_renseigne]) if champ_files.blank?
    champ_files.each do |file|
      if bad_extension(File.extname(file.filename))
        add_message(champ.label, file.filename, @params[:message_type_de_fichier])
        next
      end
      check_file(champ, file)
    end
  end

  private

  def check_file(champ, champ_file)
    PieceJustificativeCache.get(champ_file) do |file|
      case File.extname(file)
      when '.xls', '.xlsx'
        check_xlsx(champ, file)
      when '.csv'
        check_csv(champ, file)
      end
    end
  end

  def download(url, extension)
    Tempfile.create(['res', extension]) do |f|
      f.binmode
      IO.copy_stream(URI.parse(url).open, f)
      f.rewind
      yield f
    end
  end

  def bad_extension(extension)
    extension = extension&.downcase
    extension.nil? || (!extension.end_with?('.xlsx') && !extension.end_with?('.csv') && !extension.end_with?('.xls'))
  end

  def check_xlsx(champ, file)
    xlsx = Roo::Spreadsheet.open(file)
    sheets_to_control.each do |sheet_name|
      check_sheet(champ, xlsx.sheet(sheet_name), sheet_name, self.class::COLUMNS, self.class::CHECKS)
    rescue Roo::HeaderRowNotFoundError => e
      columns = e.message.gsub(%r{[/\[\]]}, '')
      add_message(champ.label, champ.file.filename, "#{@params[:message_colonnes_manquantes]}: #{columns}")
      nil
    rescue RangeError
      add_message(champ.label, champ.file.filename,
                  "Impossible de trouver la feuille #{sheet_name}. Avez vous utilisé le bon modèle de fichier Excel ?")
    end
  end

  def sheets_to_control
    []
  end

  def id_of(row)
    "#{row[:nom]} #{row[:prenoms]}".strip
  end

  def check_sheet(champ, sheet, sheet_name, columns, checks)
    rows = sheet.parse(columns).reject { |line| id_of(line).blank? || header?(columns, line) }
    field_name = "#{champ.label}/#{sheet_name}"
    apply_checks(checks, field_name, rows)
  end

  def apply_checks(checks, field_name, rows)
    rows.each do |row|
      id = id_of(row)
      checks.each do |name|
        method = "check_#{name.to_s.downcase}"
        v = send(method, row)
        unless [true, nil].include?(v)
          message = v.is_a?(String) ? v : @params[:"message_#{name}"]
          add_message(field_name, id, message)
        end
      end
    end
  end

  def header?(columns, line)
    value = line&.first&.second
    value.is_a?(String) && value.match?(columns.first[1])
  end

  def check_format_dn(line)
    dn = line[:numero_dn] || line['Numéro DN']
    dn = dn.to_i.to_s if dn.is_a? Float
    dn = dn.to_s.gsub(/\s+/, '')
    return check_format_date_de_naissance(line) if dn.match?(/^\d{6,7}$/)

    "#{@params[:message_format_dn]}: #{dn}" if dn.present?
  end

  DATE = /^\s*(?<day>\d\d?)\D(?<month>\d\d?)\D(?<year>\d{2,4})\s*$/

  def check_format_date_de_naissance(line)
    ddn = normalize_date_de_naissance(line)
    return check_cps(line) if ddn.is_a? Date

    "#{@params[:message_format_date_de_naissance]}:#{ddn}"
  end

  # good_range = (Date.iso8601('1920-01-01')..18.years.ago).cover?(ddn)

  def normalize_date_de_naissance(line)
    ddn = line[:date_de_naissance] || line['Date de naissance']
    case ddn
    when Integer, Float
      ddn = Date.new(1899, 12, 30) + line[:date_de_naissance].days
    when String
      ddn.gsub!(%r{[-:./]}, '-')
      if (match = ddn.match(/(\d+)-(\d+)-(\d+)/))
        day, month, year = match.captures.map(&:to_i)
        year += 2000 if year < 100
        year -= 100 if year > Date.today.year
        ddn = Date.new(year, month, day)
      end
    end
    line[:date_de_naissance] = ddn
  end

  def check_nom(line)
    value = line[:nom] || line[:nom_marital] || line['Nom']
    invalides = value&.scan(%r{[^[:alpha:] \-/'’()]+})
    invalides.present? ? @params[:message_nom_invalide] + invalides.join(' ') : true
  end

  def check_prenoms(line)
    value = line[:prenoms] || line['Prénom(s)'] || line['Prénom'] || line[:prenom] || ''
    invalides = value.scan(%r{[^[:alpha:] \-,/'’()]+})
    invalides.present? ? "#{@params[:message_prenom_invalide]}: #{invalides.join(' ')}" : true
  end

  def check_cps(line)
    dn = line[:numero_dn] || line['Numéro DN']
    dn = dn.to_i if dn.is_a? Float
    dn = dn.to_s if dn.is_a? Integer
    dn.gsub!(/\s+/, '')
    dn = dn.rjust(7, '0')
    ddn = line[:date_de_naissance]

    result = @cps.verify({ dn => ddn })
    case result[dn]
    when 'true'
      true
    when 'false'
      "#{@params[:message_date_de_naissance]}: #{dn},#{ddn}"
    else
      "#{@params[:message_dn]}: #{dn},#{ddn}"
    end
  end

  def check_empty_columns(line)
    missing_columns = self.class::REQUIRED_COLUMNS.filter_map do |column_name|
      value = line[column_name]
      column_name unless value && value.to_s.length.positive?
    end
    missing_columns.empty? || "#{@params[:message_colonnes_vides]}: #{missing_columns.join(',')}"
  end
end
