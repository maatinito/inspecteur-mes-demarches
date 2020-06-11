# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'

class ResExcel < FieldChecker
  def initialize(params)
    super(params)
    @cps = Cps::API.new
  end

  def version
    13
  end

  def required_fields
    %i[champ message_type_de_fichier
       message_colonnes_manquantes
       message_format_dn
       message_format_date_de_naissance
       message_dn
       message_date_de_naissance
       message_nom_invalide
       message_prenom_invalide
       message_champ_non_renseigne]
  end

  def authorized_fields
    []
  end

  Columns = {
    nom: /Nom/,
    prenoms: /Prénoms/,
    numero_dn: /Numéro DN/,
    date_de_naissance: /Date de naissance/,
    type_de_contrat: /Type de contrat de travail/,
    debut_contrat: /Date début/,
    salaire_decembre: /décembre 2019/,
    salaire_janvier: /janvier 2020/,
    salaire_fevrier: /février 2020/,
    salaire_mars: /mars 2020/,
    jours_suspendus: /suspendus/
  }.freeze

  Checks = %i[format_dn nom prenoms].freeze

  def check_xlsx(champ, file)
    xlsx = Roo::Spreadsheet.open(file)
    sheet = xlsx.sheet(0)
    rows = sheet.parse(Columns).reject { |line| line[:prenoms].nil? || line[:prenoms] =~ /Prénom/ }
    rows.each do |line|
      nom = line[:nom]
      prenoms = line[:prenoms]
      Checks.each do |name|
        method = 'check_' + name.to_s.downcase
        v = send(method, line)
        unless v == true
          message = v.is_a?(String) ? v : @params[('message_' + name.to_s).to_sym]
          add_message(champ.label, nom + ' ' + prenoms, message)
        end
      end
    end
  rescue Roo::HeaderRowNotFoundError => e
    puts e.backtrace
    columns = e.message.gsub(%r{[/\[\]]}, '')
    add_message(champ.label, champ.file.filename, @params[:message_colonnes_manquantes] + ':' + columns)
  end

  def check_csv(champ, localfile)
    # code here
  end

  def check(dossier)
    champs = field(dossier, @params[:champ])
    if champs.present?
      champs.each do |champ|
        file = champ.file
        if file.present?
          filename = file.filename
          url = file.url
          extension = filename.match /(\.[^.]+)$/
          extension &&= extension[1].downcase
          if bad_extension(extension)
            add_message(champ.label, file.filename, @params[:message_type_de_fichier])
            return
          end
          check_file(champ, extension, url)
        else
          throw StandardError.new "Le champ #{@params[:champ]} n'est pas renseigné"
          # add_message(champ.label, '', @params[:message_champ_non_renseigne])
        end
      end
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
      f.write open(url).read
      f.rewind
      yield f
    end
  end

  def bad_extension(extension)
    extension.nil? || (!extension.end_with?('.xlsx') && !extension.end_with?('.csv') && !extension.end_with?('.xls'))
  end

  def check_format_dn(line)
    dn = line[:numero_dn]
    dn = dn.to_s if dn.is_a? Integer
    dn = dn.to_i.to_s if dn.is_a? Float
    return check_format_date_de_naissance(line) if dn.is_a?(String) && dn.gsub(/\s+/, '').match?(/^\d{6,7}$/)

    @params[:message_format_dn] + ':' + dn
  end

  DATE = /^\s*(?<day>\d\d?)\D(?<month>\d\d?)\D(?<year>\d{2,4})\s*$/

  def check_format_date_de_naissance(line)
    ddn = line[:date_de_naissance]
    if ddn.is_a?(String) && (m = ddn.match(DATE))
      begin
        year = m[:year].to_i
        if year < 100
          year += (year + 2000) <= Date.today.year ? 2000 : 1900
        end
        ddn = Date.parse("#{m[:day]}/#{m[:month]}/#{year}")
      rescue StandardError
      end
    end

    if ddn.is_a? Date
      good_range = (Date.iso8601('1920-01-01')..Date.iso8601('2002-06-01')).cover?(ddn)
      return check_cps(line) if good_range
    end

    @params[:message_format_date_de_naissance] + ':' + ddn.to_s
  end

  def check_nom(line)
    value = line[:nom]
    invalides = value.scan(%r{[^[:alpha:] \-/'()]+})
    invalides.present? ? @params[:message_nom_invalide] + invalides.join(' ') : true
  end

  def check_prenoms(line)
    value = line[:prenoms]
    invalides = value.scan(%r{[^[:alpha:] \-,/'()]+})
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
      @params[:message_date_de_naissance] + ': ' + dn + ',' + ddn.to_s
    else
      @params[:message_dn] + ': ' + dn + ',' + ddn.to_s
    end
  end
end
