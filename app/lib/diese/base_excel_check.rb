# frozen_string_literal: true

module Diese
  class BaseExcelCheck < ExcelCheck
    def version
      super + 1
    end

    def required_fields
      super + %i[message_colonnes_vides]
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
  end
end
