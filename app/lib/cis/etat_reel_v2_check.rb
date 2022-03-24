# frozen_string_literal: true

module Cis
  class EtatReelV2Check < ExcelCheck
    include Shared

    def version
      super + 10
    end

    def required_fields
      super + %i[champ_candidats_admis message_colonnes_vides message_absence message_personnes_inconnues message_personnes_manquantes]
    end

    COLUMNS = {
      nom: /Nom de famille/,
      prenoms: /Prénom/,
      date_de_naissance: /Date de naissance/,
      numero_dn: /DN/,
      absences: /Jours d'absences/,
      aide: /Aide/
    }.freeze

    CHECKS = %i[format_dn nom prenoms empty_columns absence].freeze

    REQUIRED_COLUMNS = %i[numero_dn absences].freeze

    def sheets_to_control
      ['Personnes']
    end

    def id_of(row)
      "#{row[:nom]} #{row[:prenoms]}"
    end

    def check_sheet(champ, sheet, sheet_name, columns, checks)
      @posted_dns = Set.new
      super(champ, sheet, sheet_name, columns, checks)
      check_people_are_valid(champ, sheet)
    end

    def check_absence(line)
      @posted_dns << "#{line[:prenoms]} #{line[:nom]}"

      absence = line[:absences]
      absence.present? && (0..30).include?(absence.to_i)
    end

    CSV_COLUMNS = ['DN', 'NOM PATRONYMIQUE', "NOM D'EPOUSE", 'PRENOM', 'DATE NAISSANCE', 'MONTANT', 'PERIODE', 'N° CONVENTION'].to_h { |c| [c, Regexp.new(Regexp.quote(c), 'i')] }.freeze

    def check_people_are_valid(champ, sheet)
      dossier_nb = sheet.cell(4, 'C')&.to_i
      return if dossier_nb_is_invalid?(champ, dossier_nb)

      DossierActions.on_dossier(dossier_nb) do |dossier|
        return dossier_check_people_are_valid(champ, dossier)
      end
    end

    private

    def dossier_nb_is_invalid?(champ, dossier_nb)
      return false if dossier_nb > 290_000

      add_message(champ.label, champ.file.filename, 'Le fichier Excel ne semble pas avoir le bon format car le numéro de dossier est introuvable en C4.')
      true
    end

    def dossier_empty(champ, dossier)
      return if dossier.present?

      add_message(champ.label, champ.file.filename, "Impossible de lire le dossier #{dossier_nb}")
      true
    end

    def dossier_check_people_are_valid(champ, dossier)
      return if dossier_empty(champ, dossier)

      champ = dossier_annotations(dossier, @params[:champ_candidats_admis])&.first
      return if champ&.file.nil?

      champ_check_people_are_valid(champ)
    end

    def champ_check_people_are_valid(champ)
      PieceJustificativeCache.get(champ.file) do |file|
        table = Roo::Spreadsheet.open(file, { csv_options: { col_sep: ';' } })
        sheet = table.sheet(0)
        admitted = sheet.parse(CSV_COLUMNS)
        admitted = Set.new(admitted.map { |person| "#{person['PRENOM']} #{person['NOM PATRONYMIQUE']}" })
        missing = admitted - @posted_dns
        add_set_message(:message_personnes_manquantes, missing) if missing.present?
        unknown = @posted_dns - admitted
        add_set_message(:message_personnes_inconnues, unknown) if missing.present?
      end
    end

    def add_set_message(message_type, set)
      message = "#{@params[message_type]}: #{set.to_a.join(',')}"

      add_message(@params[:champ], param_field(:champ).file.filename, message)
    end
  end
end
