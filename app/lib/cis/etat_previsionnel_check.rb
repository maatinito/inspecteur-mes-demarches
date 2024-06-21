# frozen_string_literal: true

module Cis
  class EtatPrevisionnelCheck < ExcelCheck
    include Shared

    def version
      super + 11
    end

    def required_fields
      super + %i[message_colonnes_vides message_cis_demandes message_age]
    end

    def authorized_fields
      super + %i[message_secteur_activite]
    end

    COLUMNS = {
      nom: /Nom de famille/,
      prenoms: /Prénom/,
      date_de_naissance: /Date de naissance/,
      numero_dn: /DN/,
      civilite: /Civilité/,
      niveau_etudes: /Niveau d'étude/,
      date_de_naissance_conjoint: /naissance du\s+conjoint/,
      numero_dn_conjoint: /DN du conjoint/,
      nb_enfants: /Nb d'enfants/,
      activite: /Activité/
    }.freeze

    CHECKS = %i[format_dn format_dn_conjoint nom prenoms empty_columns employee_age].freeze

    REQUIRED_COLUMNS = %i[nom prenoms numero_dn civilite niveau_etudes activite].freeze

    def sheets_to_control
      ['Stagiaires']
    end

    def check_sheet(champ, sheet, sheet_name, columns, checks)
      super
      check_cis_demandes(cis_count(sheet))
    end

    def cis_count(sheet)
      sheet.cell(8, 'C')&.to_i
    end

    private

    def check_format_dn_conjoint(line)
      line[:numero_dn_conjoint].blank? ||
        check_format_dn({
                          numero_dn: line[:numero_dn_conjoint],
                          date_de_naissance: line[:date_de_naissance_conjoint]
                        })
    end
  end
end
