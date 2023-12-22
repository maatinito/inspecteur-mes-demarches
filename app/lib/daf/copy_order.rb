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

      create_orders(get_orders)
    end

    def create_orders(orders)
      return if orders.blank?

      annotation = SetAnnotationValue.allocate_blocks(@dossier,@demarche.instructeur, @params[:bloc_destination], orders.size)
      champ_destination_label = @params[:champ_destination]
      champs = annotation.champs.filter { |c| c.label == champ_destination_label }
      raise StandardError, "Impossible de copier la demande dans les annotations (#{champs.size} champs != #{orders.size} demandes)" if orders.size != champs.size

      changed = false
      orders.zip(champs).each do |order, champ|
        value = champ.respond_to?(:string_value) ? champ.string_value : champ.value
        if order != value
          SetAnnotationValue.raw_set_value(dossier.id, demarche.instructeur, champ.id, order) unless order == value
          changed = true
        end
      end
      dossier_updated(@dossier) if changed
    end

    private

    def get_orders
      rows = param_field(:champ_source).rows
      return if rows.blank?

      rows.map do |row|
        @params[:valeur].present? ? instanciate(@params[:valeur], row) : champs_to_values(row.champs).join(', ')
      end
    end
  end
end
