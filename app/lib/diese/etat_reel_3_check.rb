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
      dossier_field(initial_dossier, ACTIVITY_FIELD_NAME)
    end

    def initial_dossier
      @initial_dossier ||= retrieve_initial_dossier
    end

    MONTHS = %w[zero janvier février mars avril mai juin juillet août septembre octobre novembre décembre].freeze
    MONTH_FIELD_NAME = 'Année / Mois'

    private

    def must_check_rate?
      dossier_annotations(initial_dossier, 'En erreur').present?
    end

    def retrieve_initial_dossier
      initial_dossier_field = field(INITIAL_DOSSIER_FIELD_NAME)
      raise "Impossible de trouver le dossier prévisionnel via le champ #{INITIAL_DOSSIER_FIELD_NAME}" if initial_dossier_field.nil?

      dossier_number = initial_dossier_field.string_value&.to_i
      result = nil
      if dossier_number.present?
        DossierActions.on_dossier(dossier_number) do |dossier|
          result = dossier
        end
      end
      raise "Mes-Démarche n'a pas retourné le sous-dossier #{initial_dossier_field.string_value} à partir du dossier #{dossier.number}" if result.nil?

      result
    end

    def month
      @month ||= report_index(initial_dossier, field(MONTH_FIELD_NAME)&.secondary_value)
    end

    def report_index(dossier, month)
      # DIESE initial
      start_month = dossier_field(dossier, 'Mois 1', warn_if_empty: false)&.value&.downcase
      start_month = dossier_field(dossier, 'Mois M', warn_if_empty: false)&.value&.downcase if start_month.nil?
      if start_month.nil?
        # CSE initial
        start_month = dossier_field(dossier, 'Date de démarrage de la mesure (Mois 1)', warn_if_empty: false)&.value
        start_month = Date.parse(start_month).month if start_month.present?
      end
      if start_month.nil?
        # Avenant
        mois2 = dossier_field(dossier, 'Nombre de salariés DiESE au mois 2', warn_if_empty: false)
        if mois2.present?
          start_month = mois2.value.blank? ? 11 : 12
        end
      end
      raise "Le dossier initial #{dossier.number} n'a pas de champ permettant de connaitre le mois de démarrage de la mesure. (champ mois_1?)" if start_month.nil?

      start_month = MONTHS.index(start_month) if start_month.is_a?(String)
      current_month = MONTHS.index(month.downcase)
      raise "Impossible de reconnaitre les mois de démarrage (#{start_month})" if start_month.nil?

      raise "Impossible de reconnaitre les mois de l'etat en cours (#{month})" if current_month.nil?

      current_month += 12 if current_month < start_month
      current_month - start_month
    end
  end
end
