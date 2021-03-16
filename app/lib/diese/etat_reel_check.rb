# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'
module Diese
  class EtatReelCheck < EtatPrevisionnelCheck
    def version
      super + 10
    end

    REQUIRED_COLUMNS = EtatPrevisionnelCheck::REQUIRED_COLUMNS + %i[dmo].freeze
  end
end
