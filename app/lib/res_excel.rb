# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'

class ResExcel < FieldChecker
  def initialize(params)
    super
    @cps = Cps::API.new
  end

  def version
    super + 16
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

  COLUMNS = {
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

  CHECKS = %i[format_dn nom prenoms].freeze

  def check_xlsx(champ, file)
    xlsx = Roo::Spreadsheet.open(file)
    sheet = xlsx.sheet(0)
    rows = sheet.parse(COLUMNS).reject { |line| line[:prenoms].nil? || line[:prenoms] =~ /Prénom/ }
    rows.each do |line|
      nom = line[:nom]
      prenoms = line[:prenoms]
      CHECKS.each do |name|
        method = "check_#{name.to_s.downcase}"
        v = send(method, line)
        unless v == true
          message = v.is_a?(String) ? v : @params[:"message_#{name}"]
          add_message(champ.label, "#{nom} #{prenoms}", message)
        end
      end
    end
  rescue Roo::HeaderRowNotFoundError => e
    puts e.backtrace
    columns = e.message.gsub(%r{[/\[\]]}, '')
    add_message(champ.label, champ.file.filename, "#{@params[:message_colonnes_manquantes]}:#{columns}")
  end

  def check_csv(champ, localfile)
    # code here
  end

  def check(dossier)
    champs = dossier_fields(dossier, @params[:champ])
    return if champs.blank?

    champs.each do |champ|
      file = champ.file
      raise StandardError, "Le champ #{@params[:champ]} n'est pas renseigné" unless file.present?

      filename = file.filename
      url = file.url
      extension = filename.match(/(\.[^.]+)$/)
      extension &&= extension[1].downcase
      if bad_extension(extension)
        add_message(champ.label, file.filename, @params[:message_type_de_fichier])
        next
      end
      check_file(champ, extension, url)

      # add_message(champ.label, '', @params[:message_champ_non_renseigne])
    end
  end

  DATE = /^\s*(?<day>\d\d?)\D(?<month>\d\d?)\D(?<year>\d{2,4})\s*$/

  private

  def check_file(champ, extension, url)
    download(url, extension) do |file|
      case extension
      when '.xls', '.xlsx'
        check_xlsx(champ, file)
      when '.csv'
        check_csv(champ, file)
      end
    end
  end

  def download(url, extension)
    # Valider que l'URL provient d'une source sûre (API démarches-simplifiées)
    validate_url!(url)

    Tempfile.create(['res', extension]) do |f|
      f.binmode
      # Utiliser Typhoeus au lieu de URI.open pour éviter les risques SSRF
      response = Typhoeus.get(url, followlocation: true)
      raise StandardError, "Erreur lors du téléchargement du fichier: #{response.code}" unless response.success?

      f.write response.body
      f.rewind
      yield f
    end
  end

  def validate_url!(url)
    uri = URI.parse(url)
    # Vérifier que le schéma est http ou https
    raise StandardError, 'URL invalide: schéma non autorisé' unless %w[http https].include?(uri.scheme)

    # Vérifier que l'URL provient du domaine autorisé
    graphql_host = ENV.fetch('GRAPHQL_HOST', 'https://www.mes-demarches.gov.pf')
    allowed_host = URI.parse(graphql_host).host
    raise StandardError, 'URL invalide: domaine non autorisé' unless uri.host == allowed_host

    true
  rescue URI::InvalidURIError
    raise StandardError, 'URL invalide'
  end

  def bad_extension(extension)
    extension.nil? || (!extension.end_with?('.xlsx') && !extension.end_with?('.csv') && !extension.end_with?('.xls'))
  end

  def check_format_dn(line)
    dn = line[:numero_dn]
    dn = dn.to_s if dn.is_a? Integer
    dn = dn.to_i.to_s if dn.is_a? Float
    return check_format_date_de_naissance(line) if dn.is_a?(String) && dn.gsub(/\s+/, '').match?(/^\d{6,7}$/)

    "#{@params[:message_format_dn]}:#{dn}"
  end

  def check_format_date_de_naissance(line)
    ddn = line[:date_de_naissance]
    if ddn.is_a?(String) && (m = ddn.match(DATE))
      year = m[:year].to_i
      if year < 100
        year += (year + 2000) <= Date.today.year ? 2000 : 1900
      end
      ddn = Date.parse("#{m[:day]}/#{m[:month]}/#{year}")
    end

    if ddn.is_a? Date
      good_range = (Date.iso8601('1920-01-01')..Date.iso8601('2002-06-01')).cover?(ddn)
      return check_cps(line) if good_range
    end

    "#{@params[:message_format_date_de_naissance]}:#{ddn}"
  end

  def check_nom(line)
    value = line[:nom]
    invalides = value.scan(%r{[^[:alpha:] \-/'()]+})
    invalides.present? ? @params[:message_nom_invalide] + invalides.join(' ') : true
  end

  def check_prenoms(line)
    value = line[:prenoms]
    invalides = value.scan(%r{[^[:alpha:] \-,/'()]+})
    invalides.present? ? "#{@params[:message_prenom_invalide]}: #{invalides.join(' ')}" : true
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
end
