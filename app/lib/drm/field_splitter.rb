# frozen_string_literal: true

module Drm
  class FieldSplitter < FieldChecker
    def version
      super + 1
    end

    UNKNOWN = 'Unknown'
    SEPARATOR_REGEX = %r{\s*/\s*}

    def initialize(params)
      super
      @target_attributes = Array(@params[:attributs_cibles]).map(&:strip)
    end

    def required_fields
      super + %i[champ_source attributs_cibles]
    end

    def process_row(row, output)
      source_field = dossier_field(row, params[:champ_source])
      return unless source_field&.value

      values = source_field.value.split(SEPARATOR_REGEX)

      @target_attributes.each_with_index do |attribute_name, index|
        output[attribute_name] = display(values[index])
      end
    end

    private

    def display(value)
      value.presence || UNKNOWN
    end
  end
end
