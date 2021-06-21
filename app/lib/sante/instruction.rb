# frozen_string_literal: true

module Sante
  class Instruction < FieldChecker
    def version
      super + 8
    end

    def must_check?(md_dossier)
      super || annotations_not_updated(md_dossier)
    end

    def annotations_not_updated(md_dossier)
      return false if dossier.archived

      @dossier = md_dossier
      update_needed(ADDRESS) || update_needed(FLIGHT) || update_needed(ARRIVAL[:dst_field]) || update_needed(DEPARTURE[:dst_field])
    end

    def update_needed(field_name)
      field = get_annotation(field_name)
      field.present? && (field.value.blank? || en_construction)
    end

    def check(dossier)
      if en_construction
        check_children_date_of_birth
        check_date(ARRIVAL)
        check_date(DEPARTURE)
      end
      modified = set_address | set_date(ARRIVAL) | set_date(DEPARTURE) | set_flight_number
      Check.where(dossier: dossier.number).update_all(checked_at: Time.zone.now) if modified
    end

    private

    def en_construction
      dossier.state == 'en_construction'
    end

    ADDRESS = 'Adresse retenue'

    def set_address
      return unless update_needed(ADDRESS)

      address = get_field('Adresse de quarantaine')&.value.to_s
      commune = get_field('Commune')&.value.to_s
      address += " - #{commune}" unless address.downcase.include?(commune.downcase)

      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, ADDRESS, address)
    end

    FLIGHT = 'Numéro de vol retenu'

    def set_flight_number
      return unless update_needed(FLIGHT)

      flight_number = get_field('Numéro du vol')
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, FLIGHT, flight_number.value) if flight_number&.value
    end

    def get_field(field_name)
      @dossier.champs.find { |c| c.label == field_name }
    end

    def get_annotation(field_name)
      @dossier.annotations.find { |c| c.label == field_name }
    end

    AUTH = 'Autorisation de prélèvement'
    AUTH_MESSAGE = "Vous devez donner l'autorisation d'effectuer les prélèvements sur les enfants agés de plus de 6 ans en cochant la case 'Oui - Yes'.<BR>" \
                   "You must give authorization to perform all required COVID testing for all children above 6 by checking 'Oui - Yes'."

    MINOR_MESSAGE = "La date de naissance de l'enfant doit désigner un enfant de moins de 18 ans au moment de l'arrivée en Polynésie. Un dossier séparé doit être rempli pour les enfants majeurs.<br>" \
                      'The date of birth must designate a child under 18 at departure from French Polynesia. A separate application must be filled out for child above 17.'
    FIRST_NAME = "Prénom de l'enfant"
    DATE_OF_BIRTH = "Date de naissance de l'enfant"
    CHILDREN = 'Liste des mineurs'
    CIVILITY = "Civilité de l'enfant"

    def check_child(arrival_date, child)
      date_of_birth = child[DATE_OF_BIRTH]
      return if date_of_birth.blank?

      date_of_birth = Date.iso8601(child[DATE_OF_BIRTH])

      if is_minor(arrival_date, date_of_birth)
        check_parental_authorization(arrival_date, date_of_birth)
      else
        add_message(CHILDREN, child[FIRST_NAME], @params[:too_old_child_message] || MINOR_MESSAGE)
      end
    end

    def check_parental_authorization(arrival_date, date_of_birth)
      return if @parental_authorisation_given || @parental_message_triggered

      if between_6_and_21_years_old(arrival_date, date_of_birth)
        add_message(AUTH, field_value(AUTH)&.value, @params[:autorisation_message] || AUTH_MESSAGE)
        @parental_message_triggered = true
      end
    end

    def is_minor(arrival_date, date_of_birth)
      (arrival_date - 18.years..arrival_date).cover?(date_of_birth)
    end

    def between_6_and_21_years_old(arrival_date, date_of_birth)
      (arrival_date - 18.years..arrival_date - 6.years).cover?(date_of_birth)
    end

    def check_children_date_of_birth
      arrival_date = get_date(ARRIVAL)
      return if arrival_date.blank?

      @parental_authorisation_given = field_value(AUTH)&.value == 'Oui - Yes'
      @parental_message_triggered = false

      children_fields = field_value(CHILDREN)&.champs
      child = {}
      children_fields&.each do |field|
        if field.label == CIVILITY
          check_child(arrival_date, child) if child.present?
          child = {}
        end
        child[field.label] = field.value
      end
      check_child(arrival_date, child) if child.present?
    end

    ARRIVAL = {
      dst_field: "Date d'arrivée retenue",
      src_field: "Date d'arrivée",
      message: "La date d'arrivée donnée doit être dans les 12 prochains mois. <br> " \
               'The given arrival date must be within the next 12 months.'
    }.freeze

    DEPARTURE = {
      dst_field: 'Date de départ retenue',
      src_field: 'Date de départ du vol ',
      message: 'La date de départ donnée doit être dans les 12 prochains mois. <br> ' \
               'The given departure date must be within the next 12 months.'
    }.freeze

    def set_date(config)
      return unless update_needed(config[:dst_field])

      date = get_field(config[:src_field])
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, config[:dst_field], Date.iso8601(date.value)) if date&.value
    end

    def get_date(config)
      date = field_value(config[:src_field])&.value
      date = Date.iso8601(date) if date.present?
      date
    end

    def check_date(config)
      date = get_date(config)
      return if date.nil? || (Time.zone.now..Time.zone.now + 1.year).cover?(date)

      add_message(config[:src_field], date, @params[:date_message] || config[:message])
    end

    public def authorized_fields
      super + %i[autorisation_message too_old_child_message]
    end
  end
end
