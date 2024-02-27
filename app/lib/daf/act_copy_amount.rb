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
      super + %i[champ_commande_gratuite champ_administration_gratuite]
    end

    def process(demarche, dossier)
      super
      return if dossier.state != 'en_instruction' || order_not_ready || amount_already_set

      dossier.annotations.each do |champ|
        process_orders(demarche, dossier, champ) if champ.__typename == 'RepetitionChamp'
      end
    end

    private

    def process_orders(demarche, dossier, repetition)
      amount = amount_for_repetition(repetition)
      SetAnnotationValue.set_value(dossier, demarche.instructeur, @params[:champ_montant_theorique], amount)

      daf_gratuit = field(@params[:champ_commande_gratuite])&.value.present?
      administration_gratuite = annotation(@params[:champ_administration_gratuite])&.value == 'Debet'
      SetAnnotationValue.set_value(dossier, demarche.instructeur, @params[:champ_montant], daf_gratuit || administration_gratuite ? 0 : amount)
    end

    def amount_for_repetition(repetition)
      repetition.rows.map { amount_for(file_count(_1)) }.reduce(&:+)
    end

    def amount_already_set
      annotation_present?(:champ_montant_theorique) && annotation_present?(:champ_montant)
    end

    def order_not_ready
      !annotation_present?(:champ_commande_prete)
    end

    def annotation_present?(param)
      annotation = annotation(@params[param])
      annotation.present? && (annotation.respond_to?(:value) ? annotation.value : annotation.string_value).present?
    end

    def file_count(row)
      file_field = row.champs.find { |champ| champ.__typename == 'PieceJustificativeChamp' }
      file_field&.files&.size || 0
    end

    # compute number of pages of pdf
    # def file_page_count(filename)
    #   file = File.open(filename, 'rb')
    #   text = file.read
    #   file.close
    #
    #   keyword_c = text.scan(/Count\s+(\d+)/).size
    #   keyword_t = text.scan(%r{/Type\s*/Page[^s]}).size
    #
    #   pages = [keyword_c, keyword_t].max
    #   raise "No page found in #{filename}" if pages.zero?
    #
    #   pages
    # end

    def amount_for(count)
      count * 300
    end
  end
end
