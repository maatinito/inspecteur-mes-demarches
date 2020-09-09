# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'
module Diese
  class ExcelCheck < FieldChecker
    def initialize(params)
      super(params)
      @cps = Cps::API.new
    end

    def version
      3
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
         message_champ_non_renseigne
         message_different_value]
    end

    def authorized_fields
      []
    end

    COLUMNS = {
      nom: /Nom/,
      prenoms: /Prénom/,
      date_de_naissance: /Date de naissance/,
      numero_dn: /DN/,
      taux: /Taux RTT\* appliqué/,
      intermediaire: /Montant intermédiaire de l'aide/,
      complement: /Montant du complément au titre du revenu plancher/,
      total: /Montant total du DiESE/
    }.freeze

    CHECKS = %i[format_dn nom prenoms].freeze

    def check_xlsx(champ, file)
      xlsx = Roo::Spreadsheet.open(file)
      (0..2).map { |i| check_sheet(champ, xlsx.sheet(i), xlsx.sheets[i]) }
    rescue Roo::HeaderRowNotFoundError => e
      columns = e.message.gsub(%r{[/\[\]]}, '')
      add_message(champ.label, champ.file.filename, @params[:message_colonnes_manquantes] + ': ' + columns)
      nil
    end

    FIELD_NAMES = [
      'Nombre de salariés DiESE au mois M+',
      "Montant intermédiaire de l'aide au mois M+",
      'Montant du complément au titre du revenu plancher au mois M+',
      'Montant total du DiESE au mois M+'
    ].freeze

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
        summary = check_file(champ, extension, url)
        check_procedure_numbers(dossier, summary) if summary
      else
        throw StandardError.new "Le champ #{@params[:champ]} n'est pas renseigné"
        # add_message(champ.label, '', @params[:message_champ_non_renseigne])
      end
    end

    private

    def check_procedure_numbers(dossier, summary)
      summary.each_with_index do |excel_values, m|
        puts "excel_values=#{excel_values}, m=#{m}"
        next unless excel_values && excel_values.size == FIELD_NAMES.size

        FIELD_NAMES.each_with_index do |base, i|
          name = field_name(base, m)
          value = field(dossier, name)&.first&.value&.to_i
          puts "  base=#{base}, i=#{i}, name=#{name}, value=#{value}"
          add_message(name, value, @params[:message_different_value] + ': ' + excel_values[i].round.to_s) if value != excel_values[i].round
        end
      end
    end

    def field_name(base, index)
      base + (index + 3).to_s
    end

    def check_sheet(champ, sheet, sheet_name)
      rows = sheet.parse(COLUMNS)
      employees = rows.reject { |line| line[:prenoms].nil? || line[:prenoms] =~ /Prénom/ }
      employees.each do |line|
        nom = line[:nom]
        prenoms = line[:prenoms]
        CHECKS.each do |name|
          method = 'check_' + name.to_s.downcase
          v = send(method, line)
          unless v == true
            message = v.is_a?(String) ? v : @params[('message_' + name.to_s).to_sym]
            add_message(champ.label + '/' + sheet_name, nom + ' ' + prenoms, message)
          end
        end
      end

      [employees.size, *amount_sums(champ, rows)]
    end

    def amount_sums(champ, rows)
      sums = rows.filter { |line| line[:taux] =~ /TOTAL/ }&.first
      if sums
        [sums[:intermediaire], sums[:complement], sums[:total]]
      else
        add_message(champ.label, '', @params[:message_totaux_non_trouves])
        nil
      end
    end

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

    def check_format_dn(line)
      dn = line[:numero_dn]
      dn = dn.to_s if dn.is_a? Integer
      dn = dn.to_i.to_s if dn.is_a? Float
      return check_format_date_de_naissance(line) if dn.is_a?(String) && dn.gsub(/\s+/, '').match?(/^\d{6,7}$/)

      @params[:message_format_dn] + ':' + dn
    end

    DATE = /^\s*(?<day>\d\d?)\D(?<month>\d\d?)\D(?<year>\d{2,4})\s*$/.freeze

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
        good_range = (Date.iso8601('1920-01-01')..18.years.ago).cover?(ddn)
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
end
