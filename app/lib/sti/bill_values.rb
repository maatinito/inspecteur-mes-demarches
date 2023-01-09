# frozen_string_literal: true

module Sti
  class BillValues < FieldChecker
    def version
      super + 3
    end

    TYPES = %w[transcription inscription].freeze

    def process_row(_row)
      result = {}
      total = line(result, 1500)
      total += line(result, 6000)

      total += word_line(result)
      result['Total'] = "#{total} XPF"
      result
    end

    private

    def word_line(result)
      word_nb = annotation('Nombre de mots')&.value&.to_i || ''
      total_words = (word_nb / 100.0).ceil.to_i * 1500
      result['Total mots'] = word_nb.present? ? "#{total_words} XPF" : ''
      total_words
    end

    def line(result, value)
      docs = annotation("Documents à #{value}")&.value&.to_i || ''
      total = 0
      if docs.present?
        result["Prix #{value}"] = "#{value} XPF"
        total = docs * value
        result["Total #{value}"] = "#{total} XPF"
      else
        result["Prix #{value}"] = result["Total #{value}"] = ''
      end
      total
    end
  end
end
