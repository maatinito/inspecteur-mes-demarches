# frozen_string_literal: true

module Daf
  class BillValues < FieldChecker
    def version
      super + 1
    end

    TYPES = %w[transcription inscription].freeze

    def process_row(_row, output)
      TYPES.each do |type|
        output[type.camelize] = champ_value(annotation("Montant #{type}")).to_i + champ_value(annotation("Complément #{type}")).to_i
      end
      output['Total'] = TYPES.map { |type| output[type.camelize] }.reduce(&:+)
      output
    end
  end
end
