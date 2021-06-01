# frozen_string_literal: true

module Cis
  class EtatReelCheck < ExcelCheck
    def version
      super + 1
    end

    def required_fields
      super + %i[message_colonnes_vides]
    end

    COLUMNS = {
      nom: /Nom de famille/,
      prenoms: /Prénom/,
      date_de_naissance: /Date de naissance/,
      numero_dn: /DN/,
      absences: /Jours d'absences non justifiées/,
      aide: /Aide/
    }.freeze

    CHECKS = %i[format_dn nom prenoms empty_columns].freeze

    REQUIRED_COLUMNS = %i[numero_dn absences].freeze

    def sheets_to_control
      ['Stagiaires']
    end
  end
end
