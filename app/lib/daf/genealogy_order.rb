# frozen_string_literal: true

module Daf
  class GenealogyOrder < CopyOrder
    def version
      super + 1
    end

    private

    def orders
      champ_source = param_field(:champ_source)
      return if champ_source.blank?

      dest_field = fields_configuration.keys.first
      champ_source.values.map { |v| { dest_field => v } }
    end
  end
end
