# frozen_string_literal: true

module Sante
  class IbanValues < FieldChecker
    def version
      super + 1
    end

    def process_row(row)
      result = {}
      champs = dossier.champs
      add_rib_fields(champs, result)
      add_rib_fields(row, result) if row.respond_to?(:champs) && row != dossier
      result
    end

    def add_rib_fields(champs, result)
      champs.each do |champ|
        next unless champ.label.match?(/iban/i)

        iban = IBANTools::IBAN.new(champ.value).code
        label = champ.label
        result["#{label}/Code banque"] = iban[4, 5]
        result["#{label}/Code agence"] = iban[9, 5]
        result["#{label}/Numéro de compte"] = iban[14, 11]
        result["#{label}/Clé"] = iban[25, 2]
      end
    end
  end
end
