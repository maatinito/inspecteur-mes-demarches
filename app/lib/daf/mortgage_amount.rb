# frozen_string_literal: true

module Daf
  class MortgageAmount < Daf::Amount
    def version
      super + 1
    end

    def authorized_fields
      super + %i[champs_prepaiement]
    end

    private

    def amount
      sum_of(:champs_source) - sum_of(:champs_prepaiement)
    end

    def sum_of(champs)
      names = @params[champs]
      source_champs_names = names.is_a?(Array) ? names : names&.split(',')
      source_champs_names&.flat_map { |name| champs_to_values(annotations(name)) }&.map(&:to_i)&.reduce(&:+).to_i
    end
  end
end
