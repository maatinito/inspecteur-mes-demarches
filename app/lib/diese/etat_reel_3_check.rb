# frozen_string_literal: true

#----- TO BE TESTED

module Diese
  class EtatReel3Check < EtatReelCheck
    include RateCheck

    def version
      super + 1 + rate_check_version
    end

    ACTIVITY_FIELD_NAME = "Votre secteur d'activité"
    INITIAL_DOSSIER_FIELD_NAME = 'Numéro dossier DiESE'

    def activity_field
      field(initial_dossier, ACTIVITY_FIELD_NAME)&.first
    end

    def initial_dossier
      initial_dossier_field = field_value(INITIAL_DOSSIER_FIELD_NAME)
      throw "Impossible de trouver le dossier prévisionnel via le champ #{INITIAL_DOSSIER_FIELD_NAME}" if initial_dossier_field.nil?

      dossier_number = initial_dossier_field.string_value
      result = nil
      if dossier_number.present?
        on_dossier(dossier_number) do |dossier|
          result = dossier
        end
      end
      if result.nil?
        throw "Mes-Démarche n'a pas retourné le sous-dossier #{initial_dossier_field.string_value} à partir du dossier #{dossier.number}"
      end
      result
    end
  end
end
