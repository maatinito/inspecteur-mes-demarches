# frozen_string_literal: true

module Daf
  class GenealogyAmount < Daf::Amount
    def version
      super + 1
    end

    def initialize(params)
      super(params)
      names = @params[:champs_source]
      @source_champs_names = names.is_a?(Array) ? names : names&.split(',')
    end

    def process_row(row, output)
      output['fiches'] = count_files
    end

    private

    def amount
      200 * count_files
    end

    def count_files
  @source_champs_names&.flat_map { |name| annotations(name) }&.flat_map(&:files)&.size.to_i
    end
  end
end
