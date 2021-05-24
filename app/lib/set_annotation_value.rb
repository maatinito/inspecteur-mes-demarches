# frozen_string_literal: true

class SetAnnotationValue
  def self.set_value(md_dossier, instructeur_id, annotation_name, value)
    annotation = get_annotation(md_dossier, annotation_name)
    if annotation.present?
      old_value = annotation.__typename == 'DateChamp' && annotation.value.present? ? Date.iso8601(annotation.value) : annotation.value
      different_value = old_value != value
      raw_set_value(md_dossier.id, instructeur_id, annotation.id, value) if different_value
      different_value
    else
      Rails.logger.error("Unable to find annotation '#{annotation_name}' on dossier #{md_dossier.number}")
      false
    end
  end

  def self.raw_set_value(dossier_id, instructeur_id, annotation_id, value)
    query = case value
            when String
              Queries::SetText
            when Date
              Queries::SetDate
            when Integer
              Queries::SetInteger
            when TrueClass, FalseClass
              Queries::SetCheckBox
            end
    result = MesDemarches::Client.query(query, variables:
      {
        dossier_id: dossier_id,
        instructeur_id: instructeur_id,
        annotation_id: annotation_id,
        value: value,
        client_mutation_id: 'set_value'
      })
    throw StandardError.new result.errors if result.errors.present?
  end

  def self.get_annotation(md_dossier, name)
    md_dossier.annotations.find { |champ| champ.label == name }
  end

  Queries = MesDemarches::Client.parse <<-'GRAPHQL'
    mutation SetCheckBox($dossier_id: ID!, $instructeur_id: ID!, $annotation_id: ID!, $value: Boolean!, $client_mutation_id: String!) {
      dossierModifierAnnotationCheckbox(input: {
        dossierId: $dossier_id,
        instructeurId: $instructeur_id,
        annotationId: $annotation_id,
        value: $value,
        clientMutationId: $client_mutation_id
	    }) {
        clientMutationId
        errors {
            message
        }
      }
    }

    mutation SetDate($dossier_id: ID!, $instructeur_id: ID!, $annotation_id: ID!, $value: ISO8601Date!, $client_mutation_id: String!) {
      dossierModifierAnnotationDate(input: {
        dossierId: $dossier_id,
        instructeurId: $instructeur_id,
        annotationId: $annotation_id,
        value: $value,
        clientMutationId: $client_mutation_id
	    }) {
        clientMutationId
        errors {
            message
        }
      }
    }

    mutation SetText($dossier_id: ID!, $instructeur_id: ID!, $annotation_id: ID!, $value: String!, $client_mutation_id: String!) {
      dossierModifierAnnotationText(input: {
        dossierId: $dossier_id,
        instructeurId: $instructeur_id,
        annotationId: $annotation_id,
        value: $value,
        clientMutationId: $client_mutation_id
	    }) {
        clientMutationId
        errors {
            message
        }
      }
    }

    mutation SetInteger($dossier_id: ID!, $instructeur_id: ID!, $annotation_id: ID!, $value: Int!, $client_mutation_id: String!) {
      dossierModifierAnnotationIntegerNumber(input: {
        dossierId: $dossier_id,
        instructeurId: $instructeur_id,
        annotationId: $annotation_id,
        value: $value,
        clientMutationId: $client_mutation_id
	    }) {
        clientMutationId
        errors {
            message
        }
      }
    }
  GRAPHQL
end
