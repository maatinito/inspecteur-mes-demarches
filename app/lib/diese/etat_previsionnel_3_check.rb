# frozen_string_literal: true

module Diese
  class EtatPrevisionnel3Check < EtatPrevisionnelCheck
    include RateCheck

    def version
      super + 1 + rate_check_version
    end

    def activity_field
      field("Votre secteur d'activité")
    end

    private

    def must_check_rate
      annotations('En erreur').present?
    end

    attr_reader :month

    def check_sheet(champ, sheet, sheet_name, columns, checks)
      m = sheet_name.match(/([0-9])/)
      throw 'Unable to find month number ' unless m
      @month = m[1].to_i - 1

      super
    end
  end
end
