# frozen_string_literal: true

module Cis
  class GenererModeleEtatReel < FieldChecker
    include Cis::Shared

    CSV_COLUMNS = ['DN', 'NOM PATRONYMIQUE', "NOM D'EPOUSE", 'PRENOM', 'DATE NAISSANCE', 'MONTANT', 'PERIODE', 'N° CONVENTION'].to_h { |c| [c, Regexp.new(Regexp.quote(c), 'i')] }.freeze
    ABSENCE_COLUMNS = {
      'Nom de famille' => 'NOM PATRONYMIQUE',
      'Prénom(s)' => 'PRENOM',
      'Date de naissance' => 'DATE NAISSANCE',
      'Numéro DN' => 'DN',
      'Civilité' => '',
      "Niveau d'études" => '',
      'Date de naissance du conjoint' => '',
      'Numéro DN du conjoint' => '',
      "Nombre d'enfants" => '',
      'Activité' => '',
      'Code ROME' => '',
      "Jours d'absences non justifiées" => '',
      'Aide' => '=IF(OR(ISBLANK(INDIRECT("C"&ROW())),ISBLANK(INDIRECT("L"&ROW()))),"",ROUND(50000*(30-INDIRECT("L"&ROW()))/30,5))'
    }.freeze

    HIDDEN_COLUMNS = ['Numéro DN',
                      'Civilité',
                      "Niveau d'études",
                      'Date de naissance du conjoint',
                      'Numéro DN du conjoint',
                      "Nombre d'enfants",
                      'Activité',
                      'Code ROME'].freeze

    UNLOCKED_COLUMNS = Set.new(["Jours d'absences non justifiées"])

    def must_check?(md_dossier)
      md_dossier&.state == 'accepte'
    end

    def version
      super + 1
    end

    def required_fields
      super + %i[champ_candidats_admis date month index message nom_fichier]
    end

    def authorized_fields
      super + %i[mot_de_passe]
    end

    def process(demarche, dossier)
      super(demarche, dossier)
      champ = dossier_annotations(dossier, @params[:champ_candidats_admis])&.first
      return if champ&.file.nil?

      PieceJustificativeCache.get(champ.file) do |file|
        table = Roo::Spreadsheet.open(file, { csv_options: { col_sep: ';' } })
        sheet = table.sheet(0)
        admitted = sheet.parse(CSV_COLUMNS)
        absences = sheet_data(admitted)
        variables = {
          'Periode' => @params[:month],
          'Dossier' => dossier.number,
          'Mois' => @params[:index]
        }
        save_excel(dossier, absences, variables) do |path|
          body = instanciate(@params[:message], variables)
          filename = build_filename(@params[:nom_fichier], variables)
          SendMessage.send_with_file(dossier, demarche.instructeur, body, path, filename)
          dossier_updated(@dossier) # to prevent infinite check
        end
      end
    end

    def save_excel(dossier, rows, variables)
      Tempfile.create(['file', '.xlsx']) do |f|
        f.binmode
        excel_writer = build_excel_writer(dossier, variables)
        excel_writer.write(rows, f, columns: ABSENCE_COLUMNS.keys)
        f.rewind
        yield f
      end
    end

    private

    def sheet_data(admitted)
      admitted.map do |row|
        ABSENCE_COLUMNS.to_h do |column, expression|
          value = expression.starts_with?('=') ? expression : row[expression]
          [column, value]
        end
      end
    end

    def build_excel_writer(dossier, variables)
      company_name = dossier.demandeur.entreprise.nom_commercial.presence || dossier.demandeur.entreprise.raison_sociale
      ExcelWriter.new.tap do |e|
        e.variables = variables
        e.title = "Relevé d'absences pour #{company_name}"
        e.unlocked_columns = UNLOCKED_COLUMNS
        e.hidden_columns = HIDDEN_COLUMNS
        e.password = @params[:mot_de_passe]
      end
    end
  end
end
