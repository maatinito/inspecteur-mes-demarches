# frozen_string_literal: true

module Sante
  class Instruction < FieldChecker
    def version
      super + 1
    end

    def check(_dossier)
      # check_children_date_of_birth
      modified = set_address | set_arrival_date | set_flight_number
      Check.where(dossier: dossier.number).update_all(checked_at: Time.zone.now) if modified
    end

    private

    ADDRESS = 'Adresse retenue'

    def set_address
      return unless get_annotation(ADDRESS)

      address = "#{get_field('Adresse de quarantaine')&.value} - #{get_field('Commune')&.value}"
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, ADDRESS, address)
    end

    FLIGHT = 'Numéro de vol retenu'

    def set_flight_number
      return unless get_annotation(FLIGHT)

      flight_number = get_field('Numéro du vol')
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, FLIGHT, flight_number.value) if flight_number&.value
    end

    ARRIVAL = "Date d'arrivée retenue"

    def set_arrival_date
      return unless get_annotation(ARRIVAL)

      date = get_field("Date d'arrivée")
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, ARRIVAL, Date.iso8601(date.value)) if date&.value
    end

    def get_field(field_name)
      @dossier.champs.find { |c| c.label == field_name }
    end

    def get_annotation(field_name)
      @dossier.annotations.find { |c| c.label == field_name }
    end

    def check_children_date_of_birth
      children = field_values('Liste des mineurs')
      pp children
    end


  end
end
