# frozen_string_literal: true

module Diese
  class EtatPrevisionnel3Check < EtatPrevisionnelCheck
    include RateCheck

    def version
      super + 1 + rate_check_version
    end

    def activity_field
      field_value("Votre secteur d'activité")
    end
  end
end
