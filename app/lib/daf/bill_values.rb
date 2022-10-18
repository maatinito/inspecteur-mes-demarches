# frozen_string_literal: true

module Daf
  class BillValues < FieldChecker
    def version
      super + 1
    end

    TYPES = %w[transcription inscription].freeze

    def process_row(_row)
      result = {}
      TYPES.each do |type|
        result[type.camelize] = annotation("Montant #{type}")&.value.to_i + annotation("Complément #{type}")&.value.to_i
      end
      result['Total'] = TYPES.map { |type| result[type.camelize] }.reduce(&:+)
      result
    end
  end
end
