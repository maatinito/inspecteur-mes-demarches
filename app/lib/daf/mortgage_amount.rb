# frozen_string_literal: true

module Daf
  class MortgageAmount < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[champ_cible champs_source]
    end

    def authorized_fields
      super + %i[champ_declencheur etats_du_dossier]
    end

    def process(demarche, dossier)
      super
      return unless dossier_has_right_state && trigger_field_set && amount_not_set

      names = @params[:champs_source]
      @source_champs_names ||= names.is_a?(Array) ? names : names&.split(',')
      amount = @source_champs_names.flat_map { |name| champs_to_values(annotations(name)) }.map(&:to_i).reduce(&:+)
      SetAnnotationValue.set_value(dossier, demarche.instructeur, @params[:champ_cible], amount) unless amount.nil?
    end

    private

    def dossier_has_right_state
      @states ||= right_states
      @states.include?(@dossier.state)
    end

    def right_states
      states = @params[:etats_du_dossier]
      states = states.split(',') if states.is_a?(String)
      Set[*states.presence || 'en_construction']
    end

    def amount_not_set
      annotation(@params[:champ_cible])&.value.blank?
    end

    def trigger_field_set
      @params[:champ_declencheur].blank? || annotation(@params[:champ_declencheur])&.value
    end
  end
end
