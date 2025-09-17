# frozen_string_literal: true

module Diese
  class EtatPrevisionnelCheck < BaseExcelCheck
    def version
      super + 6
    end

    def required_fields
      super + %i[message_different_value]
    end

    def check_sheet(champ, sheet, sheet_name, columns, checks)
      super
      check_dossier_numbers(sheet, sheet_name)
    end

    FIELD_NAMES = [
      ['Nombre de salariés DiESE au mois ', 'C', 8],
      ['Montant prévisionnel du DiESE au mois ', 'C', 9]
    ].freeze

    private

    def sheets_to_control
      ['Mois 1', 'Mois 2', 'Mois 3']
    end

    def check_dossier_numbers(sheet, sheet_name)
      self.class::FIELD_NAMES.each do |base_name, column, line|
        in_excel = sheet.cell(line, column)&.to_i
        field_name = base_name + sheet_name[-1]
        in_dossier = field(field_name)&.value&.to_i
        add_message(field_name, in_dossier, "#{@params[:message_different_value]}: #{in_excel}") unless in_dossier == in_excel
      end
    end
  end
end
