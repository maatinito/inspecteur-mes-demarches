# frozen_string_literal: true

module Sante
  class OblivaccSheetCheck < ExcelCheck
    def version
      super + 1
    end

    def required_fields
      super + %i[message_colonnes_vides]
    end

    COLUMNS = {
      nom: /Nom de naissance/,
      nom_marital: /Nom marital/,
      prenoms: /Prénom/,
      date_de_naissance: /Date de naissance/,
      civilite: /Civilité/,
      numero_dn: /DN/,
      telephone: /Téléphone/,
      activite: /Activité professionnelle/
    }.freeze

    CHECKS = %i[format_dn nom prenoms empty_columns].freeze

    REQUIRED_COLUMNS = %i[nom prenoms date_de_naissance activite].freeze

    def sheets_to_control
      ['Liste personnes concernées']
    end
  end
end
