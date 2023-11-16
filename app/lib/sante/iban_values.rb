# frozen_string_literal: true

module Sante
  class IbanValues < FieldChecker
    def version
      super + 1
    end

    def process_row(row, output)
      champs = dossier.champs
      add_rib_fields(champs, output)
      add_rib_fields(row, output) if row.respond_to?(:champs) && row != dossier
      output
    end

    def add_rib_fields(champs, output)
      champs.each do |champ|
        next unless champ.label.match?(/iban/i)

        iban = IBANTools::IBAN.new(champ.value).code
        label = champ.label
        output["#{label}/Code banque"] = iban[4, 5]
        output["#{label}/Code agence"] = iban[9, 5]
        output["#{label}/Numéro de compte"] = iban[14, 11]
        output["#{label}/Clé"] = iban[25, 2]
      end
    end
  end
end
