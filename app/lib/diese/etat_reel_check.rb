# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'
module Diese
  class EtatReelCheck < BaseExcelCheck
    def version
      super + 9
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

    COTISATIONS = [6, 'J']
    SECTEUR = [8, 'A']

    def check_sheet(champ, sheet, sheet_name, columns, checks)
      super(champ, sheet, sheet_name, columns, checks)
      check_sector(champ, sheet, sheet_name)
    end

    def check_sector(champ, sheet, sheet_name)
      if sheet.cell(SECTEUR[0], SECTEUR[1])&.start_with?("Secteur d'activité")
        cotisations = sheet.cell(COTISATIONS[0], COTISATIONS[1])
        if cotisations == "#N/A"
          message = @params[:message_secteur_activite] ||
            "Le secteur d'activité doit être renseigné à l'aide du menu déroulant. (Flèche en C8)"
          add_message(champ.label + '/' + sheet_name, "Secteur d'activité en C8", message)
        end
      end
    end

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