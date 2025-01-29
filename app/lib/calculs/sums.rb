# frozen_string_literal: true

module Calculs
  class Sums < FieldChecker
    def version
      super + 1
    end

    def add_sums(output, _label, table)
      table.each do |row|
        row.each do |variable, value|
          if value.is_a?(Numeric)
            sum_variable = "#{variable}.Total"
            output[sum_variable] = (output[sum_variable] || 0) + value
          end
        end
      end
    end

    def process_row(_dossier, output)
      sums = {}
      output.each do |label, values|
        add_sums(sums, label, values) if values.is_a?(Array) && values.present? && values.first.is_a?(Hash)
      end
      output.merge!(sums)
    end
  end
end
