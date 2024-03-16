# frozen_string_literal: true

module Calculs
  class RepetitionCount < FieldChecker
    def version
      super + 1
    end

    def process_row(dossier, output)
      [*dossier.annotations, *dossier.champs].filter { |c| c.__typename == 'RepetitionChamp' }.each do |champ|
        output["#{champ.label}.count"] = output["#{champ.label}.nombre"] = champ.rows.count
      end
    end
  end
end
