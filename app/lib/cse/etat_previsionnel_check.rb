# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'
module Cse
  class EtatPrevisionnelCheck < Diese::EtatPrevisionnelCheck
    def version
      super + 1
    end

    def authorized_fields
      super + %i[message_secteur_activite]
    end

    private

    def sheets_to_control
      ['Mois 1', 'Mois 2', 'Mois 3', 'Mois 4', 'Mois 5', 'Mois 6']
    end

    FIELD_NAMES = [
      ['Nombre de salariés CSE au mois ', 'H', 4],
      ['CSE brut mois ', 'H', 5],
      ['Cotisations mois ', 'H', 6]
    ].freeze

    def check_sheet(champ, sheet, sheet_name, columns, checks)
      super
      check_sector(champ, sheet, sheet_name)
    end

    COTISATIONS = [9, 'C'].freeze
    SECTEUR = [8, 'A'].freeze

    def check_sector(champ, sheet, sheet_name)
      return unless sheet.cell(SECTEUR[0], SECTEUR[1])&.start_with?("Secteur d'activité")

      cotisations = sheet.cell(COTISATIONS[0], COTISATIONS[1])
      return true if cotisations != '#N/A'

      message = @params[:message_secteur_activite] ||
                "Le secteur d'activité doit être renseigné à l'aide du menu déroulant. (Flèche en C8)"
      add_message("#{champ.label}/#{sheet_name}", "Secteur d'activité en C8", message)
    end
  end
end
