# frozen_string_literal: true

module Sti
  class BillValues < FieldChecker
    def version
      super + 2
    end

    TYPES = %w[transcription inscription].freeze

    def process_row(_row)
      result = {}
      docs1500 = annotation('Documents à 1500')&.value&.to_i || ''
      docs6000 = annotation('Documents à 6000')&.value&.to_i || ''
      word_nb = annotation('Nombre de mots')&.value&.to_i || ''
      total = 0

      if docs1500.present?
        result['Prix 1500'] = '1500 XPF'
        total_1500 = docs1500 * 1500
        total += total_1500
        result['Total 1500'] = "#{total_1500} XPF"
      else
        result['Prix 1500'] = result['Total 1500'] = ''
      end

      if docs6000.present?
        result['Prix 6000'] = '6000 XPF'
        total_6000 = docs6000 * 6000
        total += total_6000
        result['Total 6000'] = "#{total_6000} XPF"
      else
        result['Prix 6000'] = result['Total 6000'] = ''
      end

      total_words = (word_nb / 100.0).ceil.to_i * 1500
      total += total_words
      result['Total mots'] = word_nb.present? ? "#{total_words} XPF" : ''
      result['Total'] = "#{total} XPF"
      result
    end
  end
end
