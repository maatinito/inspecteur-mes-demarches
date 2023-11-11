# frozen_string_literal: true

module Sti
  class TotalPrice < FieldChecker
    def version
      super + 2
    end

    TOTAL_PRICE = 'Prix total'

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      if annotation_already_set(TOTAL_PRICE)
        Rails.logger.info("Dossier ignored as #{name} is already set")
        return
      end
      if dossier.archived
        Rails.logger.info('Dossier ignored as it is archived')
        return
      end

      set_total_price
    end

    private

    def annotation_already_set(name)
      field = annotation(name)
      field.present? && field.value.present?
    end

    def set_total_price
      total = price_for(1500)
      total += price_for(6000)
      total += price_for(200)
      total += price_for_words
      total += price_for_copies
      dossier_updated(@dossier) if SetAnnotationValue.set_value(@dossier, @demarche.instructeur, TOTAL_PRICE, total)
    end

    def price_for_words
      word_nb = annotation('Nombre de mots')&.value&.to_i || 0
      return 0 if word_nb.zero?

      (word_nb / 100.0).ceil.to_i * 1500
    end

    def price_for_copies
      page_nb = annotation('Pages de copies')&.value&.to_i || 0
      return 0 if page_nb.zero?

      page_nb * 100
    end

    def price_for(doc_type)
      doc_count = annotation("Traductions à #{doc_type}")&.value&.to_i || 0
      doc_count * doc_type
    end
  end
end
