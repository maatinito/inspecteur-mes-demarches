# frozen_string_literal: true

module Diese
  class EtatReelCheck < BaseExcelCheck
    def version
      super + 11
    end

    REQUIRED_COLUMNS = EtatPrevisionnelCheck::REQUIRED_COLUMNS + %i[dmo].freeze

    def sheets_to_control
      ['Etat']
    end
  end
end
