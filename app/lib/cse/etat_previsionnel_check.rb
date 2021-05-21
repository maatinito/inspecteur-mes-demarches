# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'
module Cse
  class EtatPrevisionnelCheck < Diese::EtatPrevisionnelCheck
    def version
      super + 1
    end

    private

    COTISATIONS = [6, 'J'].freeze
    SECTEUR = [8, 'A'].freeze

    def check_sheet(champ, sheet, sheet_name)
      super(champ, sheet, sheet_name)
      check_sector(champ, sheet, sheet_name)
    end

    def check_sector(champ, sheet, sheet_name)
      return unless sheet.cell(SECTEUR[0], SECTEUR[1])&.start_with?("Secteur d'activité")

      cotisations = sheet.cell(COTISATIONS[0], COTISATIONS[1])
      return if cotisations != '#N/A'

      message = @params[:message_secteur_activite] ||
                "Le secteur d'activité doit être renseigné à l'aide du menu déroulant. (Flèche en C8)"
      add_message("#{champ.label}/#{sheet_name}", "Secteur d'activité en C8", message)
    end
  end
end
