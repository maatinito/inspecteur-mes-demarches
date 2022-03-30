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
      throw "Unable to find annotation '#{annotation_name}' on dossier #{md_dossier.number}"
    end
  end

  def self.set_piece_justificative(md_dossier, instructeur_id, annotation_name, path, filename = File.basename(path))
    annotation = get_annotation(md_dossier, annotation_name)
    if annotation.present?
      old_checksum = annotation.file&.checksum
      new_checksum = FileUpload.checksum(path)
      different_file = old_checksum != new_checksum
      if different_file
        attachment = FileUpload.upload_file(md_dossier.id, path, filename, new_checksum)
        raw_set_piece_justificative(md_dossier.id, instructeur_id, annotation.id, attachment)
      end
    else
      throw "Unable to find annotation '#{annotation_name}' on dossier #{md_dossier.number}"
    end
  end

  def self.raw_set_value(dossier_id, instructeur_id, annotation_id, value)
    result = MesDemarches::Client.query(typed_query(value), variables:
      {
        dossier_id: dossier_id,
        instructeur_id: instructeur_id,
        annotation_id: annotation_id,
        value: value,
        client_mutation_id: 'set_value'
      })
    errors = result.errors&.values&.flatten.presence || result.data.to_h.values.first['errors']
    throw errors.join(';') if errors.present?
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

    mutation SetPieceJustificative($dossier_id: ID!, $instructeur_id: ID!, $annotation_id: ID!, $attachment_id: ID!, $client_mutation_id: String!) {
      dossierModifierAnnotationPieceJustificative(input: {
        dossierId: $dossier_id
        instructeurId: $instructeur_id
        annotationId: $annotation_id
        attachment: $attachment_id
        clientMutationId: $client_mutation_id
      }) {
        clientMutationId
        errors {
          message
        }
      }
    }
  GRAPHQL

  def self.typed_query(value)
    case value
    when String
      Queries::SetText
    when Date
      Queries::SetDate
    when Integer
      Queries::SetInteger
    when TrueClass, FalseClass
      Queries::SetCheckBox
    else
      throw "Unable to know which graphql request to call with value of type #{value.class.name}"
    end
  end

  def self.raw_set_piece_justificative(dossier_id, instructeur_id, annotation_id, attachment_id)
    result = MesDemarches::Client.query(Queries::SetPieceJustificative, variables:
      {
        dossier_id: dossier_id,
        instructeur_id: instructeur_id,
        annotation_id: annotation_id,
        attachment_id: attachment_id,
        client_mutation_id: 'set_value'
      })
    errors = result.errors&.values&.flatten.presence || result.data.to_h.values.first['errors']
    throw errors.join(';') if errors.present?
    result.data
  end
end