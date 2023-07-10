# frozen_string_literal: true

module Calculs
  class AmountInLetters < FieldChecker
    include ActionView::Helpers::NumberHelper

    def version
      super + 1
    end

    def process_row(dossier)
      [*dossier.champs, *dossier.annotations].each_with_object({}) do |champ, result|
        if /Montant/.match(champ.label)
          result["#{champ.label} en lettres"] = (champ.value || 0).to_i&.humanize&.to_s
          result["#{champ.label} en chiffres"] = number_to_currency(champ.value || 0, unit: "", separator: ",", delimiter: " ", precision: 0)
        end
      end
    end
  end
end
