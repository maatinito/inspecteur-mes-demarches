# frozen_string_literal: true

module Calculs
  class FloatToPercent < FieldChecker
    include ActionView::Helpers::NumberHelper

    def required_fields
      super + %i[champ]
    end

    def version
      super + 1
    end

    def process_row(_dossier, output)
      return unless @params[:champ].present?

      float_to_percent(output, @params[:champ])
    end

    private

    def float_to_percent(input, field)
      if input.is_a?(Array)
        input.each { |row| float_to_percent(row, field) }
      elsif input.is_a?(Hash)
        if (match = field.match(/([^.]+)\.(.*)/))
          float_to_percent(input[match[1]], match[2])
        elsif input[field].is_a?(Numeric)
          input[field] = "#{input[field] * 100}%"
        end
      end
    end
  end
end
