# frozen_string_literal: true

module Daf
  class ActCopyAmount < FieldChecker
    def version
      super + 3
    end

    def required_fields
      super + %i[champ_montant champ_montant_theorique champ_commande_prete]
    end

    def authorized_fields
      super + %i[champ_commande_gratuite champ_agent]
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
      SetAnnotationValue.set_value(dossier, demarche.instructeur, @params[:champ_montant_theorique], amount)

      commande_gratuite = @params.key?(:champ_commande_gratuite) && field(@params[:champ_commande_gratuite])&.value.present?
      agent = @params.key?(:champ_agent) && annotation(@params[:champ_agent])&.value == 'Oui'
      SetAnnotationValue.set_value(dossier, demarche.instructeur, @params[:champ_montant], commande_gratuite && agent ? 0 : amount)
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
      page_field = champs.find { |champ| champ.__typename == 'IntegerNumberChamp' }
      pages = page_field&.value.to_i
      return pages if pages.positive?

      file_field = champs.find { |champ| champ.__typename == 'PieceJustificativeChamp' }
      return 0 if file_field&.file&.filename.blank?

      PieceJustificativeCache.get(file_field.file) do |file|
        pages = file_page_count(file)
        if page_field
          Rails.logger.info("Setting #{page_field.label} to #{pages}")
          SetAnnotationValue.raw_set_value(@dossier.id, @demarche.instructeur, page_field.id, pages)
        end
        return pages
      end
    end

    def file_page_count(filename)
      file = File.open(filename, 'rb')
      text = file.read
      file.close

      keyword_c = text.scan(/Count\s+(\d+)/).size
      keyword_t = text.scan(%r{/Type\s*/Page[^s]}).size

      pages = keyword_c > keyword_t ? keyword_c : keyword_t
      throw "No page found in #{filename}" if pages.zero?

      pages
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
