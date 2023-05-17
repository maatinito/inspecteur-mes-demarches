# frozen_string_literal: true

module Cis
  class CalculeActivite < FieldChecker
    def version
      super + 4
    end

    COLUMNS = ['Numéro DN', 'Activité'].to_h { |c| [c, Regexp.new(Regexp.quote(c), 'i')] }.freeze

    UNKNOWN = 'Inconnue'

    def process(_demarche, dossier)
      { 'Activité' => get_activite(dossier) }
    end

    private

    def get_activite(dossier)
      field = dossier_field(dossier, 'Numéro de dossier CIS')
      return UNKNOWN if field.blank?

      numero_dn_field = dossier_field(dossier, 'Numéro DN')
      return UNKNOWN if numero_dn_field.blank?

      numero_dn = numero_dn_field.numero_dn.to_i

      DossierActions.on_dossier(field.string_value.to_i) do |dossier_oa|
        return get_activite_from_oa(dossier_oa, numero_dn)
      end
    rescue StandardError => e
      Rails.logger.error(e.message)
      e.backtrace.select { |b| b.include?('/app/') }.first(7).each { |b| Rails.logger.error(b) }
      UNKNOWN
    end

    def get_activite_from_oa(dossier_oa, numero_dn)
      candidat_field = dossier_annotations(dossier_oa, 'Candidats')&.first
      return UNKNOWN if candidat_field.blank?

      PieceJustificativeCache.get(candidat_field.file) do |xlsx_file|
        return get_activite_from_candidats(xlsx_file, numero_dn)
      rescue Roo::HeaderRowNotFoundError => e
        columns = e.message.gsub(%r{[/\[\]]}, '')
        raise "Colonne(s) manquante(s) dans les données de consolidation: #{columns}"
      end
    end

    def get_activite_from_candidats(xlsx_file, numero_dn)
      xlsx = Roo::Spreadsheet.open(xlsx_file)
      xlsx.sheet(0).each(COLUMNS) do |row|
        return row['Activité'] if row['Numéro DN'] == numero_dn
      end
      UNKNOWN
    end
  end
end
