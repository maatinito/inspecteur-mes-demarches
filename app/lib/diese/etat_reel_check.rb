# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'
module Diese
  class EtatReelCheck < BaseExcelCheck
    def version
      super + 7
    end

    def required_fields
      super + %i[
        message_colonnes_vides
      ]
    end

    COLUMNS = {
      nom: /Nom de famille/,
      nom_marital: /Nom marital/,
      prenoms: /Prénom/,
      date_de_naissance: /Date de naissance/,
      numero_dn: /DN/,
      heure_avant_convention: /Heures avant convention/,
      brut_mensuel_moyen: /Brut mensuel moyen/,
      heures_a_realiser: /Heures à réaliser/,
      dmo: /DMO/,
      jours_non_remuneres: /Jours non rémunérés/,
      jours_indemnites_journalieres: /Jours d'indemnités journalières/,
      taux: /Taux RTT/,
      aide: /Aide/,
      cotisations: /Cotisations/,
      p_temps_present: /% temps présent/,
      p_realise: /% réalisé convention/,
      p_perte_salaire: /% perte salaire/,
      p_aide: /% aide/,
      plafond: /plafond/,
      aide_maximale: /aide maximale/
    }.freeze

    CHECKS = %i[format_dn nom prenoms empty_columns].freeze

    def check_xlsx(champ, file)
      xlsx = Roo::Spreadsheet.open(file)
      check_sheet(champ, xlsx.sheet(0), xlsx.sheets[0], COLUMNS, CHECKS)
    rescue Roo::HeaderRowNotFoundError => e
      columns = e.message.gsub(%r{[/\[\]]}, '')
      add_message(champ.label, champ.file.filename, @params[:message_colonnes_manquantes] + ': ' + columns)
      nil
    end

    private

    REQUIRED_COLUMNS = %i[heure_avant_convention brut_mensuel_moyen heures_a_realiser dmo]

    def check_empty_columns(line)
      missing_columns = REQUIRED_COLUMNS.filter_map do |column_name|
        value = line[column_name]
        column_name unless value && value.to_s.length > 0 && value.to_f >= 0
      end
      missing_columns.empty? || @params[:message_colonnes_vides] + missing_columns.join(',')
    end
  end
end