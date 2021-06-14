# frozen_string_literal: true

module Sante
  class Instruction < FieldChecker
    def version
      super + 4
    end

    def check(_dossier)
      check_children_date_of_birth
      check_arrival_date

      modified = set_address | set_arrival_date | set_flight_number
      Check.where(dossier: dossier.number).update_all(checked_at: Time.zone.now) if modified
    end

    private

    ADDRESS = 'Adresse retenue'

    def set_address
      return unless get_annotation(ADDRESS)

      address = get_field('Adresse de quarantaine')&.value.to_s
      commune = get_field('Commune')&.value.to_s
      address += " - #{commune}" unless address.downcase.include?(commune.downcase)

      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, ADDRESS, address)
    end

    FLIGHT = 'Numéro de vol retenu'

    def set_flight_number
      return unless get_annotation(FLIGHT)

      flight_number = get_field('Numéro du vol')
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, FLIGHT, flight_number.value) if flight_number&.value
    end

    KEPT_ARRIVAL_DATE = "Date d'arrivée retenue"

    ARRIVAL_DATE = "Date d'arrivée"
    ARRIVAL_DATE_MESSAGE = "La date d'arrivée donnée doit être dans les 12 prochains mois. <br> " +
      "The given arrival date must be within the next 12 months."

    def set_arrival_date
      return unless get_annotation(KEPT_ARRIVAL_DATE)

      date = get_field(ARRIVAL_DATE)
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, KEPT_ARRIVAL_DATE, Date.iso8601(date.value)) if date&.value
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
                      'The date of birth must designate a child under 18 at arrival in French Polynesia. A separate application must be filled out for child above 17.'
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
      arrival_date = get_arrival_date
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

    def get_arrival_date
      arrival_date = field_value(ARRIVAL_DATE)&.value
      arrival_date = Date.iso8601(arrival_date) if arrival_date.present?
      arrival_date
    end

    def check_arrival_date
      arrival_date = get_arrival_date
      return if (Time.zone.now..Time.zone.now + 1.year).include?(arrival_date)

      add_message(ARRIVAL_DATE, arrival_date, @params[:arriaval_date_message] || ARRIVAL_DATE_MESSAGE)
    end

    public def authorized_fields
      super + %i[autorisation_message too_old_child_message]
    end
  end
end
