# frozen_string_literal: true

module Sante
  class Instruction < FieldChecker
    def version
      super + 1
    end

    def check(_dossier)
      check_children_date_of_birth
      check_parental_authorization
      modified = set_address | set_arrival_date | set_flight_number
      Check.where(dossier: dossier.number).update_all(checked_at: Time.zone.now) if modified
    end

    private

    ADDRESS = 'Adresse retenue'

    def set_address
      return unless get_annotation(ADDRESS)
      address = get_field('Adresse de quarantaine')&.value.to_s
      commune = get_field('Commune')&.value.to_s
      address += " - " + commune unless address.downcase.include?(commune.downcase)

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

    TOO_OLD_MESSAGE = "L'enfant est majeur au moment de l'arrivée en Polynésie. Un dossier séparé doit être rempli.<br>" +
      'The child is above 18 at arrival date: a separate application must be filled out for him.'
    FIRST_NAME = "Prénom de l'enfant"
    DATE_OF_BIRTH = "Date de naissance de l'enfant"
    CHILDREN = 'Liste des mineurs'
    CIVILITY = "Civilité de l'enfant"

    def check_child(arrival_date, child)
      date_of_birth = child[DATE_OF_BIRTH]
      return if date_of_birth.blank?

      date_of_birth = Date.iso8601(child[DATE_OF_BIRTH])
      return if (arrival_date - 18.years..arrival_date).include?(date_of_birth)

      add_message(CHILDREN, child[FIRST_NAME], @params[:too_old_child_message] || TOO_OLD_MESSAGE)
    end

    def check_children_date_of_birth
      arrival_date = get_arrival_date
      return if arrival_date.blank?

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
      arrival_date = get_annotation(KEPT_ARRIVAL_DATE)&.value
      arrival_date = field_value(ARRIVAL_DATE)&.value if arrival_date.blank?
      arrival_date = Date.iso8601(arrival_date) if arrival_date.present?
      arrival_date
    end

    AUTH = "Autorisation de prélèvement"
    AUTH_MESSAGE = "L'autorisation doit être donnée pour pouvoir effectuer des prélèvements sur les enfants.<BR>" +
      "The authorisation must be given to be able to perform all required COVID testing for all children."

    def check_parental_authorization
      children_fields = field_value(CHILDREN)&.champs
      return if children_fields.blank?

      parental_authorisation = field_value(AUTH)&.value
      return if parental_authorisation == 'Oui - Yes'

      add_message(AUTH, parental_authorisation, @params[:autorisation_message] || AUTH_MESSAGE)
    end

    public def authorized_fields
      super + %i[autorisation_message too_old_child_message]
    end
  end
end
