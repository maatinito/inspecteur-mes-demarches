# frozen_string_literal: true

module Cse
  class EtatReelCheck < EtatPrevisionnelCheck
    def version
      super + 1
    end

    REQUIRED_COLUMNS = EtatPrevisionnelCheck::REQUIRED_COLUMNS + %i[dmo].freeze
  end
end
