# frozen_string_literal: true

module Diese
  class EtatPrevisionnelCheck < ExcelCheck
    def version
      super + 4
    end

    def required_fields
      super + %i[message_colonnes_vides]
    end

    def authorized_fields
      super + %i[message_secteur_activite]
    end

    COLUMNS = {
      nom: /Nom de famille/,
      nom_marital: /Nom marital/,
      prenoms: /Prénom/,
      date_de_naissance: /Date de naissance/,
      numero_dn: /DN/,
      heure_avant_convention: /Heures avant /,
      brut_mensuel_moyen: /Brut mensuel moyen/,
      heures_a_realiser: /Heures à réaliser/,
      dmo: /DMO/,
      jours_non_remuneres: /Jours non rémunérés|Jours d'absence/,
      jours_indemnites_journalieres: /Jours d'indemnités journalières/,
      taux: /Taux RTT/,
      aide: /Aide/,
      cotisations: /Cotisations/,
      p_temps_present: /% temps présent/,
      p_realise: /% réalisé convention|% convention effectuée/,
      p_perte_salaire: /% perte salaire/,
      p_aide: /% aide/,
      plafond: /plafond/,
      aide_maximale: /aide maximale/
    }.freeze

    CHECKS = %i[format_dn nom prenoms empty_columns].freeze

    REQUIRED_COLUMNS = %i[heure_avant_convention brut_mensuel_moyen heures_a_realiser].freeze

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
