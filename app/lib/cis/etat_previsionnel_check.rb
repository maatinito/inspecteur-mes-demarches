# frozen_string_literal: true

module Cis
  class EtatPrevisionnelCheck < ExcelCheck
    def version
      super + 10
    end

    def required_fields
      super + %i[message_colonnes_vides message_cis_demandes]
    end

    def authorized_fields
      super + %i[message_secteur_activite]
    end

    COLUMNS = {
      nom: /Nom de famille/,
      prenoms: /Prénom/,
      date_de_naissance: /Date de naissance/,
      numero_dn: /DN/,
      civilite: /Civilité/,
      niveau_etudes: /Niveau d'étude/,
      date_de_naissance_conjoint: /naissance du\s+conjoint/,
      numero_dn_conjoint: /DN du conjoint/,
      nb_enfants: /Nb d'enfants/,
      activite: /Activité/
    }.freeze

    CHECKS = %i[format_dn format_dn_conjoint nom prenoms empty_columns].freeze

    REQUIRED_COLUMNS = %i[nom prenoms civilite niveau_etudes activite].freeze

    def check_sheet(champ, sheet, sheet_name, columns, checks)
      super(champ, sheet, sheet_name, columns, checks)
      check_cis_demandes(sheet)
    end

    private

    CIS_DEMANDES_CELL = [8, 'C'].freeze
    CIS_DEMANDES_FIELD = 'Nombre de CIS demandés'

    def check_cis_demandes(sheet)
      in_excel = sheet.cell(CIS_DEMANDES_CELL[0], CIS_DEMANDES_CELL[1])&.to_i
      in_dossier = field_value(CIS_DEMANDES_FIELD)&.value&.to_i
      if in_dossier != in_excel
        message = @params[:message_cis_demandes] ||
                  'Le nombre de cis demandes doit être égal au nombre de candidats dans le fichier Excel: '
        add_message(CIS_DEMANDES_FIELD, in_dossier, message + ': ' + in_excel.to_s)
      end
    end

    def check_format_dn_conjoint(line)
      line[:numero_dn_conjoint].blank? ||
        check_format_dn({
                          numero_dn: line[:numero_dn_conjoint],
                          date_de_naissance: line[:date_de_naissance_conjoint]
                        })
    end
  end
end
