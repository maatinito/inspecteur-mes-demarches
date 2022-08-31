# frozen_string_literal: true

module Daf
  class MortgageFirstAmounts < FieldChecker
    def version
      super + 1
    end

    def process(demarche, dossier)
      super
      return if dossier.state != 'en_construction'

      set_amount(demarche, dossier, 'TRANSCRIPTION', 'Montant transcription')
      set_amount(demarche, dossier, 'INSCRIPTION', 'Montant inscription')
    end

    private

    def set_amount(demarche, dossier, champ_declencheur, champ_montant)
      amount = field(champ_declencheur)&.value ? 500 : 0
      SetAnnotationValue.set_value(dossier, demarche.instructeur, champ_montant, amount)
    end
  end
end
