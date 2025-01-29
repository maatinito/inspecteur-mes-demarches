# frozen_string_literal: true

module Daf
  class CopyOrder < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[champ_source bloc_destination champ_destination]
    end

    def authorized_fields
      super + %i[valeur]
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      create_orders(orders)
    end

    def create_orders(orders)
      return if orders.blank?

      target_repetition = SetAnnotationValue.allocate_blocks(@dossier, @demarche.instructeur, @params[:bloc_destination], orders.size)
      champ_destination_label = @params[:champ_destination]
      annotations = target_repetition.champs.filter { |c| c.label == champ_destination_label }
      missing = annotations.size - orders.size
      orders = [*orders, *Array.new(missing, '')] if missing.positive?

      changed = false
      orders.zip(annotations).each do |order, annotation|
        next if order.blank? || order == SetAnnotationValue.value_of(annotation)

        SetAnnotationValue.raw_set_value(dossier.id, demarche.instructeur, annotation.id, order)
        changed = true
      end
      dossier_updated(@dossier) if changed
    end

    private

    def orders
      rows = param_field(:champ_source).rows
      return if rows.blank?

      rows.map do |row|
        @params[:valeur].present? ? instanciate(@params[:valeur], row) : champs_to_values(row.champs).join(', ')
      end
    end
  end
end
