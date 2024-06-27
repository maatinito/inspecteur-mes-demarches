# frozen_string_literal: true

class SetAnnotationValue
  def self.set_value(md_dossier, instructeur_id, annotation_name, value)
    annotation = get_annotation(md_dossier, annotation_name)
    raise "Unable to find annotation '#{annotation_name}' on dossier #{md_dossier.number}" unless annotation.present?

    old_value = value_of(annotation)
    different_value = old_value != value
    if different_value
      Rails.logger.info("Setting private annotation #{annotation_name} with #{value}")
      raw_set_value(md_dossier.id, instructeur_id, annotation.id, value)
    else
      Rails.logger.info("Private annotation #{annotation_name} already set to #{value}")
    end
    different_value
  end

  def self.set_piece_justificative(md_dossier, instructeur_id, annotation_name, path, filename = File.basename(path))
    annotation = get_annotation(md_dossier, annotation_name)
    raise "Unable to find annotation '#{annotation_name}' on dossier #{md_dossier.number}" unless annotation.present?

    set_piece_justificative_on_annotation(md_dossier, instructeur_id, annotation, path, filename)
  end

  def self.set_piece_justificative_on_annotation(md_dossier, instructeur_id, annotation, path, filename)
    new_checksum = FileUpload.checksum(path)
    same_file = annotation.files.find { _1.checksum == new_checksum }
    return if same_file

    attachment = FileUpload.upload_file(md_dossier.id, path, filename, new_checksum)
    raw_set_piece_justificative(md_dossier.id, instructeur_id, annotation.id, attachment)
  end

  def self.allocate_blocks(md_dossier, instructeur_id, annotation_name, block_count)
    annotation = get_annotation(md_dossier, annotation_name)
    raise "Unable to find annotation '#{annotation_name}' on dossier #{md_dossier.number}" unless annotation.present?

    count = count_block_in(annotation.champs)
    result = annotation
    (count...block_count).each do
      result = raw_add_block(md_dossier.id, instructeur_id, annotation.id)
    end
    result
  end

  def self.raw_set_value(dossier_id, instructeur_id, annotation_id, value)
    result = MesDemarches.query(typed_query(value), variables:
      {
        dossier_id:,
        instructeur_id:,
        annotation_id:,
        value:,
        client_mutation_id: 'set_value'
      })
    errors = result.errors&.values&.flatten.presence || result.data.to_h.values.first['errors']
    raise errors.join(';') if errors.present?

    result
  end

  def self.get_annotation(md_dossier, name)
    md_dossier.annotations.find { |champ| champ.label == name }
  end

  def self.raw_add_block(dossier_id, instructeur_id, annotation_id)
    result = MesDemarches.query(Queries::AddBlock, variables:
      {
        dossier_id:,
        instructeur_id:,
        annotation_id:,
        client_mutation_id: 'add_block'
      })
    errors = result.errors&.values&.flatten.presence || result.data.to_h.values.first['errors']
    raise errors.join(';') if errors.present?

    result.data.dossier_modifier_annotation_ajouter_ligne.annotation
  end

  def self.count_block_in(champs)
    return 0 if champs.empty?

    label = champs.first.label
    champs.count { |c| c.label == label }
  end

  Queries = MesDemarches::Client.parse <<-GRAPHQL
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

    mutation AddBlock($dossier_id: ID!, $instructeur_id: ID!, $annotation_id: ID!, $client_mutation_id: String!) {
      dossierModifierAnnotationAjouterLigne(
        input: {
          dossierId: $dossier_id
          instructeurId: $instructeur_id
          annotationId: $annotation_id
          clientMutationId: $client_mutation_id
        }
      ) {
        clientMutationId
        errors {message }
        __typename
        annotation {
          champs {
            id
            label
            stringValue
          }
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
      raise "Unable to know which graphql request to call with value of type #{value.class.name}"
    end
  end

  def self.raw_set_piece_justificative(dossier_id, instructeur_id, annotation_id, attachment_id)
    result = MesDemarches.query(Queries::SetPieceJustificative, variables:
      {
        dossier_id:,
        instructeur_id:,
        annotation_id:,
        attachment_id:,
        client_mutation_id: 'set_value'
      })
    pp result
    errors = result.errors&.values&.flatten.presence || result.data.to_h.values.first['errors']
    raise errors.join(';') if errors.present?

    result.data
  end

  def self.value_of(annotation)
    value = if annotation.respond_to?(:value)
              annotation.value
            else
              annotation.string_value
            end
    if value.present?
      case annotation.__typename
      when 'DateChamp'
        value = Date.iso8601(annotation.value)
      when 'IntegerNumberChamp'
        value = value.to_i
      end
    end
    value
  end
end
