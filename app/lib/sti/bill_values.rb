# frozen_string_literal: true

module Sti
  class BillValues < FieldChecker
    def version
      super + 3
    end

    TYPES = %w[transcription inscription].freeze

    def process_row(row, output)
      bill = []
      add_product(row, bill, 'Nombre de mots', 'Traductions au mot') { |count| (count / 100.0).ceil.to_i * 1500 }
      add_product(row, bill, 'Traductions à 1500') { |count| count * 1500 }
      add_product(row, bill, 'Traductions à 2000') { |count| count * 2000 }
      add_product(row, bill, 'Traductions à 6000') { |count| count * 6000 }
      add_product(row, bill, 'Traductions à 200') { |count| count * 200 }
      add_product(row, bill, 'Pages de copies') { |count| count * 100 }

      output['Lignes'] = bill

      total = bill.reduce(0) { |sum, line| sum + line[:total] }
      output['Total'] = total
      output['Total en lettres'] = "#{total.humanize.capitalize} francs"
    end

    private

    def add_product(row, bill, annotation, produit = annotation)
      quantite = dossier_annotations(row, annotation)&.first&.value.to_i
      bill << { produit:, quantité: quantite, total: yield(quantite) } if quantite.positive?
    end
  end
end
