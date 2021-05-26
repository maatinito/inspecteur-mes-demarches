# frozen_string_literal: true

module Sante
  class Instruction < InspectorTask
    def process(demarche, dossier)
      @dossier = dossier
      @demarche = demarche
      if dossier.state == 'en_construction'
        # single pipe to execute all instructions
        modified = set_address | set_arrival_date | set_departure_date | set_flight_number
        Check.where(dossier: dossier.number).update_all(checked_at: Time.zone.now) if modified
      end
    end

    private

    def set_address
      lieu_de_quarantaine = get_field('Lieu de quarantaine')&.value
      return unless lieu_de_quarantaine

      adresse = case lieu_de_quarantaine
                when 'dans votre logement'
                  "#{get_field('Adresse géographique')&.value} - #{get_field('Commune')&.value}"
                when 'en hôtel agréé'
                  get_field("Nom de l'hôtel")&.value
                when 'en site pour étudiant'
                  'en site pour étudiant'
                end
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, 'Adresse de la quarantaine retenue', adresse) if adresse
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

    DEPARTURE = 'Date de départ retenue'

    def set_departure_date
      return unless get_annotation(DEPARTURE)

      date = get_field('Date de départ')
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, DEPARTURE, Date.iso8601(date.value)) if date&.value
    end

    def get_field(field_name)
      @dossier.champs.find { |c| c.label == field_name }
    end

    def get_annotation(field_name)
      @dossier.annotations.find { |c| c.label == field_name }
    end
  end
end
