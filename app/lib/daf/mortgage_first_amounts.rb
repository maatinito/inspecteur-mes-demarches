# frozen_string_literal: true

module Daf
  class MortgageFirstAmounts < FieldChecker
    def version
      super + 1
    end

    def process(demarche, dossier)
      super
      set_certification_date(demarche, dossier)

      return if dossier.state != 'en_construction'
      return if field('Numéro Tahiti')&.string_value.present?
      return if field('Administration')&.value.present?

      set_amount(demarche, dossier, 'TRANSCRIPTION', 'Montant transcription')
      set_amount(demarche, dossier, 'INSCRIPTION', 'Montant inscription')
    end

    private

    def set_certification_date(demarche, dossier)
      certification_date_blank = annotation('DATE DE CERTIFICATION')&.value.blank?
      SetAnnotationValue.set_value(dossier, demarche.instructeur, 'DATE DE CERTIFICATION', DateTime.iso8601(dossier.date_depot)) if certification_date_blank
    end

    def set_amount(demarche, dossier, champ_declencheur, champ_montant)
      amount = field(champ_declencheur)&.value ? 500 : 0
      SetAnnotationValue.set_value(dossier, demarche.instructeur, champ_montant, amount)
    end
  end
end
