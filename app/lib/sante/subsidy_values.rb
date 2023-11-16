# frozen_string_literal: true

module Sante
  class SubsidyValues < FieldChecker
    def version
      super + 1
    end

    TYPES = %w[transcription inscription].freeze

    def process_row(_row, output)
      asked_grant = field('Montant demandé')&.value&.to_f || 1
      project_amount = field('Montant total du projet')&.value&.to_f || 1
      given_grant = annotation('Montant en chiffres')&.value&.to_f || 1
      output['Avance'] = (given_grant * 50 / 100).round
      output['Acompte'] = (given_grant * 40 / 100).round
      output['Solde'] = given_grant.round - output['Avance'] - output['Acompte']
      %w[Avance Acompte Solde].each { |k| output["#{k} en lettres"] = output[k].humanize }
      output['Pourcentage subvention'] = (given_grant / asked_grant * 100).round
      output['Pourcentage total'] = (given_grant / project_amount * 100).round

      output
    end
  end
end
