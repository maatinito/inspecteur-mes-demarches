# frozen_string_literal: true

module Daf
  class Amount < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[champ_cible champs_source]
    end

    def authorized_fields
      super + %i[champ_declencheur]
    end

    def process(demarche, dossier)
      super
      return unless dossier_has_right_state && trigger_field_set

      amount_value = amount
      return if amount_value.nil?

      changed = SetAnnotationValue.set_value(dossier, demarche.instructeur, @params[:champ_cible], amount_value)
      dossier_updated(dossier) if changed
    end

    private

    def amount
      raise NotImplementedError, 'Method should be redefined'
    end

    def dossier_has_right_state
      @states.include?(@dossier.state)
    end

    def trigger_field_set
      @params[:champ_declencheur].blank? || annotation(@params[:champ_declencheur])&.string_value.present?
    end
  end
end
