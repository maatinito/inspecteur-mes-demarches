# frozen_string_literal: true

module Daf
  class GenealogyOrder < CopyOrder
    def version
      super + 1
    end

    private

    def get_orders
      champ_source = param_field(:champ_source)
      return if champ_source.blank?

      champ_source.values
    end
  end
end
