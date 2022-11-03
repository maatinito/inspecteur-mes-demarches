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
      super + %i[champ_declencheur champs_prepaiement]
    end

    def process(demarche, dossier)
      super
      return unless dossier_has_right_state && trigger_field_set && amount_not_set

      amount = sum_of(:champs_source)
      return if amount.nil?

      amount -= sum_of(:champs_prepaiement)
      changed = SetAnnotationValue.set_value(dossier, demarche.instructeur, @params[:champ_cible], amount)
      dossier_updated(dossier) if changed
    end

    private

    def sum_of(champs)
      names = @params[champs]
      source_champs_names = names.is_a?(Array) ? names : names&.split(',')
      source_champs_names&.flat_map { |name| champs_to_values(annotations(name)) }&.map(&:to_i)&.reduce(&:+).to_i
    end

    def dossier_has_right_state
      @states.include?(@dossier.state)
    end

    def amount_not_set
      annotation(@params[:champ_cible])&.value.blank?
    end

    def trigger_field_set
      @params[:champ_declencheur].blank? || annotation(@params[:champ_declencheur])&.string_value.present?
    end
  end
end
