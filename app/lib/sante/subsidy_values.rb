# frozen_string_literal: true

module Sante
  class SubsidyValues < FieldChecker
    def version
      super + 1
    end

    TYPES = %w[transcription inscription].freeze

    def process_row(_row)
      result = {}
      asked_grant = field('Montant demandé')&.value&.to_f || 1
      project_amount = field('Montant total du projet')&.value&.to_f || 1
      given_grant = annotation('Montant en chiffres')&.value&.to_f || 1
      result['Avance'] = (given_grant * 50 / 100).round
      result['Acompte'] = (given_grant * 40 / 100).round
      result['Solde'] = given_grant.round - result['Avance'] - result['Acompte']
      result.each_key { |k| result["#{k} en lettres"] = result[k].humanize }
      result['Pourcentage subvention'] = (given_grant / asked_grant * 100).round
      result['Pourcentage total'] = (given_grant / project_amount * 100).round

      result
    end
  end
end
