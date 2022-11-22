# frozen_string_literal: true

module Drm
  class VesselAttributes < FieldChecker
    def version
      super + 1
    end

    VESSEL = 'Navire'
    UNKNOWN = 'Unknown'

    def process_row(_row)
      (name, number, length) = field(VESSEL)&.value&.split(%r{\s*/\s*})
      length.sub!(/m?$/i, 'm') if length.is_a?(String)
      number.sub!(/^(PY)?\s*/i, 'PY ') if number.is_a?(String)
      {
        'Nom_Navire' => display(name),
        'Immatriculation_Navire' => display(number),
        'Longueur_Navire' => display(length)
      }
    end

    private

    def display(value)
      value.presence || UNKNOWN
    end
  end
end
