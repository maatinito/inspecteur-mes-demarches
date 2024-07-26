# frozen_string_literal: true

module Calculs
  class AmountInLetters < FieldChecker
    include ActionView::Helpers::NumberHelper

    def version
      super + 1
    end

    def process_row(_dossier, output)
      # [*dossier.champs, *dossier.annotations].each do |champ|
      #   add_amounts(output, champ.label, champ.value) if champ.__typename == 'IntegerNumberChamp' || champ.__typename == 'DecimalNumberChamp'
      # end
      keys = output.keys # get copy to be able to add entries in hash while iterating
      keys.each do |label|
        add_amounts(output, label, output[label])
      end
    end

    private

    def add_amounts(output, label, value)
      return unless label.include?('Montant') || label.include?('TVA')

      output["#{label} en lettres"] = [*value || 0].map(&:to_i).map(&:humanize).map(&:to_s)
      output["#{label} en chiffres"] = [*value || 0].map { |v| number_to_currency(v, unit: '', separator: ',', delimiter: ' ', precision: 0) }
    end
  end
end
