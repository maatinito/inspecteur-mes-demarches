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
      new_checksum = checksum(path)
      different_file = old_checksum != new_checksum
      if different_file
        attachment = upload_file(md_dossier.id, new_checksum, path, filename)
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

    mutation CreateDirectUpload($dossier_id: ID!, $filename: String!, $byteSize: Int!, $checksum: String!, $contentType: String!) {
      createDirectUpload(input: {
        dossierId: $dossier_id,
        filename: $filename,
        byteSize: $byteSize,
        checksum: $checksum,
        contentType: $contentType,
        clientMutationId: "1"
      }) {
        clientMutationId,
        directUpload {
          headers,
          signedBlobId,
          url
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

  def self.upload_file(dossier_id, checksum, path, filename)
    slot = upload_slot(dossier_id, checksum, path, filename)
    params = slot.direct_upload
    response = Typhoeus.put(params.url, headers: JSON.parse(params.headers), body: File.read(path, mode: 'rb'))
    throw response.response_body if response.code != 200
    params.signed_blob_id
  end

  def self.upload_slot(dossier_id, checksum, path, filename)
    result = MesDemarches::Client.query(Queries::CreateDirectUpload, variables:
      {
        dossier_id: dossier_id,
        filename: filename,
        byteSize: File.size(path),
        checksum: checksum,
        contentType: (MIME::Types.type_for(path).presence || MIME::Types['text/plain']).first.to_s,
        client_mutation_id: 'upload'
      })
    errors = result.errors&.values&.flatten.presence || result.data.to_h.values.first['errors']
    throw errors.join(';') if errors.present?

    result.data&.create_direct_upload
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

  def self.checksum(file_path)
    Digest::MD5.base64digest(File.read(file_path))
  end
end
