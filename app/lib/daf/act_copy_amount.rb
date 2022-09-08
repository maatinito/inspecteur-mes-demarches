# frozen_string_literal: true

module Daf
  class ActCopyAmount < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[champ_montant champ_montant_theorique champ_commande_prete]
    end

    def authorized_fields
      super + %i[champ_commande_gratuite]
    end

    def process(demarche, dossier)
      super
      return if dossier.state == 'en_construction' || order_not_ready || amount_already_set

      dossier.annotations.each do |champ|
        process_orders(demarche, dossier, champ) if champ.__typename == 'RepetitionChamp'
      end
    end

    private

    def process_orders(demarche, dossier, repetition)
      amount = amount_for_repetition(repetition)
      SetAnnotationValue.set_value(dossier, demarche.instructeur, @params[:champ_montant_theorique], amount) unless annotation_present?(:champ_montant_theorique)

      return if annotation_present?(:champ_montant)

      commande_gratuite = field(@params[:champ_commande_gratuite])&.value.present?
      SetAnnotationValue.set_value(dossier, demarche.instructeur, @params[:champ_montant], commande_gratuite ? 0 : amount)
    end

    def amount_for_repetition(repetition)
      order = {}
      amount = 0
      repetition.champs.each do |champ|
        if order[champ.label].present?
          amount += amount_for(pages_count(order))
          order = {}
        end
        order[champ.label] = champ
      end
      amount + amount_for(pages_count(order))
    end

    def amount_already_set
      annotation_present?(:champ_montant_theorique) && annotation_present?(:champ_montant)
    end

    def order_not_ready
      !annotation_present?(:champ_commande_prete)
    end

    def annotation_present?(param)
      annotation(@params[param])&.value.present?
    end

    def pages_count(bloc)
      champs = bloc.values
      pages = champs.find { |champ| champ.__typename == 'IntegerNumberChamp' }&.value.to_i
      return pages if pages.positive?

      file_field = champs.find { |champ| champ.__typename == 'PieceJustificativeChamp' }
      return 0 if file_field&.file&.filename.blank?

      PieceJustificativeCache.get(file_field.file) do |file|
        pages = file_page_count(file)
        Rails.logger.error("Unable to compute pdf page count in dossier #{dossier.number}: #{champ.file}") if pages.zero?

        return pages
      end
    end

    def file_page_count(filename)
      file = File.open(filename, 'rb')
      text = file.read
      file.close

      keyword_c = text.scan(/Count\s+(\d+)/).size
      keyword_t = text.scan(%r{/Type\s*/Page[^s]}).size

      keyword_c > keyword_t ? keyword_c : keyword_t
    end

    def amount_for(pages)
      if pages.zero?
        0
      else
        pages >= 25 ? 600 + ((pages - 25) * 30) : 300
      end
    end
  end
end
