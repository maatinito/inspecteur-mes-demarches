# frozen_string_literal: true

module Daf
  class CopyOrder < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[champ_source bloc_destination champ_destination]
    end

    def process(demarche, dossier)
      super
      champs = param_field(:champ_source)&.champs
      return if champs.blank?

      orders = get_orders(champs)
      annotation = SetAnnotationValue.allocate_blocks(dossier, demarche.instructeur, @params[:bloc_destination], orders.size)
      champ_destination_label = @params[:champ_destination]
      champs = annotation.champs.filter { |c| c.label == champ_destination_label }
      raise StandardError, "Impossible de copier la demande dans les annotations (#{champs.size} champs != #{orders.size} demandes)" if orders.size != champs.size

      orders.zip(champs).each do |order, champ|
        value = champ.respond_to?(:string_value) ? champ.string_value : champ.value
        SetAnnotationValue.raw_set_value(dossier.id, demarche.instructeur, champ.id, order) unless order == value
      end
    end

    private

    def get_orders(champs)
      get_repetitions(champs).map do |repetition|
        repetition.map(&:value).select(&:present?).join('-')
      end
    end

    def get_repetitions(champs)
      champs.each_with_object([[]]) do |champ, result|
        result << [] if result.last.first&.label == champ.label # next line/hash
        result.last << champ
      end
    end
  end
end
