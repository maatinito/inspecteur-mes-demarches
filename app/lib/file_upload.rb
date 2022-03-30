# frozen_string_literal: true

class FileUpload
  def self.upload_file(dossier_id, path, filename, checksum = checksum(path))
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

  def self.checksum(file_path)
    Digest::MD5.base64digest(File.read(file_path))
  end

  Queries = MesDemarches::Client.parse <<-'GRAPHQL'
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
  GRAPHQL
end