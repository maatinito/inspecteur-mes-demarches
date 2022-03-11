# frozen_string_literal: true

module Cis
  class Consolidation < FieldChecker
    include Utils

    def version
      super + 13
    end

    def required_fields
      super + %i[champ_synthese champ_candidats]
    end

    def self.dn_fields(extension)
      ["Numéro DN#{extension}", "Date de naissance#{extension}"]
    end

    def must_check?(md_dossier)
      md_dossier&.state == 'en_construction' || md_dossier&.state == 'en_instruction'
    end

    private

    def set_text_attribute(dossier, field, value)
      modified = SetAnnotationValue.set_value(dossier, @demarche.instructeur, field, value)
      annotation_updated_on(@dossier_oa) if modified
    end

    def save_excel(candidats)
      Tempfile.create(['Personnes', '.xlsx']) do |f|
        f.binmode
        ExcelWriter.new.write(candidats, f, columns: COLUMN_REGEXPS.keys)
        f.rewind
        yield f
      end
    end

    # def synthese(candidats)
    #   oa_only = candidats.filter { |_dn, c| c[PRESENCE] == 'OA' }.map(&method(:display_person)).sort.join("\n")
    #   de_only = candidats.filter { |_dn, c| c[PRESENCE] == 'DE' }.map(&method(:display_person)).sort.join("\n")
    #   oa_de = candidats.filter { |_dn, c| c[PRESENCE] == 'OA+DE' }.map(&method(:display_person)).sort.join("\n")
    #   synthese = ''.dup
    #   synthese << "Candidats sans dossier individuel\n" << oa_only << "\n\n" if oa_only.present?
    #   synthese << "Candidats non déclarés par l'organisme\n" << de_only << "\n\n" if de_only.present?
    #   synthese << "Candidats déclarés\n" << oa_de if oa_de.present?
    #   synthese
    # end
    #
    # def display_person(_dn, person)
    #   display = ['Prénom', 'Nom', 'Numéro DN'].map { |f| person[f] }.join(' ')
    #   dossier = person['Dossier']
    #   display << ", dossier: #{dossier}" if dossier.present?
    #   display
    # end

    DEMANDEUR = ['Civilité', 'Nom', 'Prénom(s)'].freeze
    CHAMPS_DE = ["Niveau d'études", "Nombre d'enfants", 'Commune géographique', 'Téléphone', 'IBAN'].freeze
    ROME = 'Code ROME'
    ACTIVITE = 'Activité'
    CHAMPS_OA = [ACTIVITE, ROME].freeze
    DOSSIER = 'Dossier'

    COLUMN_REGEXPS = (
      [DOSSIER] + DEMANDEUR + dn_fields('') + CHAMPS_OA + CHAMPS_DE + dn_fields(' du conjoint')
    ).to_h { |v| [v, Regexp.new(Regexp.quote(v), 'i')] }.freeze

    OLD_COLUMN_REGEXPS = COLUMN_REGEXPS.except(ROME)

    def bad_extension(extension)
      extension = extension&.downcase
      extension.nil? || (!extension.end_with?('.xlsx') && !extension.end_with?('.csv') && !extension.end_with?('.xls'))
    end

    def candidats(dossier)
      champs = dossier_annotations(dossier, @params[:champ_candidats])
      return {} if champs.blank?

      champ = champs.first
      file = champ.file
      return {} unless file.present?

      return {} if bad_extension(File.extname(file.filename))

      PieceJustificativeCache.get(file) do |xlsx_file|
        return candidats_from_xlsx(xlsx_file)
      rescue Roo::HeaderRowNotFoundError => e
        columns = e.message.gsub(%r{[/\[\]]}, '')
        Rails.logger.error("Colonne(s) manquante(s) dans les données: #{columns} dossier #{dossier.number} ==> ignoring input")
        {}
      end
    end

    def candidats_from_xlsx(xlsx_file)
      xlsx = Roo::Spreadsheet.open(xlsx_file)
      begin
        rows = xlsx.sheet(0).parse(COLUMN_REGEXPS)
      rescue Roo::HeaderRowNotFoundError
        rows = xlsx.sheet(0).parse(OLD_COLUMN_REGEXPS)
      end
      rows.to_h { |row| [row['Numéro DN'], row] }
    end

    def set_candidats_attribute(dossier, field, candidats)
      save_excel(candidats) do |f|
        SetAnnotationValue.set_piece_justificative(dossier, @demarche.instructeur, field, f.path, "#{field}.xlsx")
        annotation_updated_on(@dossier_oa)
        PieceJustificativeCache.put(f.path)
      end
    end
  end
end
