# frozen_string_literal: true

module Payzen
  class Taxes < FieldChecker
    include ActionView::Helpers::NumberHelper

    def version
      super + 2
    end

    def required_fields
      super + %i[champ_montant_ht]
    end

    def authorized_fields
      super + %i[champ_tva champ_ttc]
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      amount = annotation(@params[:champ_montant_ht])&.value
      return if amount.blank?

      amount = amount.to_i
      tva = (amount * 0.13).round
      ttc = amount + tva

      different1 = SetAnnotationValue.set_value(@dossier, instructeur_id, @params[:champ_tva], tva) if @params[:champ_tva].present?
      different2 = SetAnnotationValue.set_value(@dossier, instructeur_id, @params[:champ_ttc], ttc) if @params[:champ_ttc].present?
      dossier_updated(@dossier) if different1 || different2
    end
  end
end
