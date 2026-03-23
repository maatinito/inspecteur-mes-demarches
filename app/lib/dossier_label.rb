# frozen_string_literal: true

class DossierLabel
  class << self
    def add(dossier_id, label_id)
      result = MesDemarches.query(mutations::AjouterLabel, variables: {
                                    dossierId: dossier_id,
                                    labelId: label_id
                                  })
      handle_errors(result)
    end

    def remove(dossier_id, label_id)
      result = MesDemarches.query(mutations::SupprimerLabel, variables: {
                                    dossierId: dossier_id,
                                    labelId: label_id
                                  })
      handle_errors(result)
    end

    def find_label_id(demarche_number, label_name)
      result = MesDemarches.query(queries::DemarcheLabels, variables: { demarche: demarche_number })
      labels = result.data&.demarche&.labels
      return nil if labels.blank?

      labels.find { |l| l.name == label_name }&.id
    end

    private

    def handle_errors(result)
      errors = result.errors&.values&.flatten.presence || result.data.to_h.values.first['errors']
      raise errors.map { |e| e['message'] }.join('; ') if errors.present?

      result
    end

    def mutations
      @mutations ||= MesDemarches::Client.parse <<-GRAPHQL
        mutation AjouterLabel($dossierId: ID!, $labelId: ID!) {
          dossierAjouterLabel(input: {
            dossierId: $dossierId,
            labelId: $labelId
          }) {
            errors { message }
          }
        }

        mutation SupprimerLabel($dossierId: ID!, $labelId: ID!) {
          dossierSupprimerLabel(input: {
            dossierId: $dossierId,
            labelId: $labelId
          }) {
            errors { message }
          }
        }
      GRAPHQL
    end

    def queries
      @queries ||= MesDemarches::Client.parse <<-GRAPHQL
        query DemarcheLabels($demarche: Int!) {
          demarche(number: $demarche) {
            labels {
              id
              name
            }
          }
        }
      GRAPHQL
    end
  end
end
