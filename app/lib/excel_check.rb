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
    super + 4
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
    champs = field(dossier, @params[:champ])
    return if champs.blank?

    champ = champs.first
    file = champ.file
    if file.present?
      filename = file.filename
      url = file.url
      extension = File.extname(filename)
      if bad_extension(extension)
        add_message(champ.label, file.filename, @params[:message_type_de_fichier])
        return
      end
      check_file(champ, extension, url)
    else
      # throw StandardError.new "Le champ #{@params[:champ]} n'est pas renseigné"
      add_message(champ.label, '', @params[:message_champ_non_renseigne])
    end
  end

  private

  def check_file(champ, extension, url)
    download(url, extension) do |file|
      case extension
      when '.xls'
        check_xlsx(champ, file)
      when '.xlsx'
        check_xlsx(champ, file)
      when '.csv'
        check_csv(champ, file)
      end
    end
  end

  def download(url, extension)
    Tempfile.create(['res', extension]) do |f|
      f.binmode
      f.write URI.open(url).read
      f.rewind
      yield f
    end
  end

  def bad_extension(extension)
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
    rescue RangeError => e
      add_message(champ.label, champ.file.filename,
                  "Impossible de trouver la feuille #{sheet_name}. Avez vous utilisé le bon modèle de fichier Excel ?")
    end
  end

  def sheets_to_control
    []
  end

  def check_sheet(champ, sheet, sheet_name, columns, checks)
    rows = sheet.parse(columns)
    employees = rows.reject { |line| line[:prenoms].nil? || line[:prenoms].strip.blank? || line[:prenoms] =~ /Prénom/ }
    employees.each do |line|
      nom = line[:nom] || line[:nom_marital]
      prenoms = line[:prenoms]
      checks.each do |name|
        method = "check_#{name.to_s.downcase}"
        v = send(method, line)
        unless v == true
          message = v.is_a?(String) ? v : @params["message_#{name}".to_sym]
          add_message("#{champ.label}/#{sheet_name}", "#{nom} #{prenoms}", message)
        end
      end
    end
  end

  def check_format_dn(line)
    dn = line[:numero_dn]
    dn = dn.to_s if dn.is_a? Integer
    dn = dn.to_i.to_s if dn.is_a? Float
    return check_format_date_de_naissance(line) if dn.is_a?(String) && dn.gsub(/\s+/, '').match?(/^\d{6,7}$/)

    "#{@params[:message_format_dn]}:#{dn}"
  end

  DATE = /^\s*(?<day>\d\d?)\D(?<month>\d\d?)\D(?<year>\d{2,4})\s*$/.freeze

  def check_format_date_de_naissance(line)
    ddn = normalize_date_de_naissance(line)
    return check_cps(line) if ddn.is_a? Date

    "#{@params[:message_format_date_de_naissance]}:#{ddn}"
  end

  # good_range = (Date.iso8601('1920-01-01')..18.years.ago).cover?(ddn)

  def normalize_date_de_naissance(line)
    ddn = line[:date_de_naissance]
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
    value = line[:nom] || line[:nom_marital]
    invalides = value&.scan(%r{[^[:alpha:] \-/'’()]+})
    invalides.present? ? @params[:message_nom_invalide] + invalides.join(' ') : true
  end

  def check_prenoms(line)
    value = line[:prenoms]
    invalides = value.scan(%r{[^[:alpha:] \-,/'’()]+})
    invalides.present? ? @params[:message_prenom_invalide] + invalides.join(' ') : true
  end

  def check_cps(line)
    dn = line[:numero_dn]
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
      column_name unless value && value.to_s.length.positive? && value.to_f >= 0
    end
    missing_columns.empty? || "#{@params[:message_colonnes_vides]}: #{missing_columns.join(',')}"
  end
end
