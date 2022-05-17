# frozen_string_literal: true

class SendMessage
  def self.send(dossier_id, instructeur_id, body)
    handle_errors(MesDemarches::Client.query(Mutation::EnvoyerMessage,
                                             variables: {
                                               dossierId: dossier_id,
                                               instructeurId: instructeur_id,
                                               body:,
                                               clientMutationId: 'foo'
                                             }))
  end

  def self.send_with_file(dossier_id, instructeur_id, body, file_path, filename)
    attachment_id = FileUpload.upload_file(dossier_id, file_path, filename)
    handle_errors(MesDemarches::Client.query(Mutation::EnvoyerMessageAvecFichier,
                                             variables: {
                                               dossierId: dossier_id,
                                               instructeurId: instructeur_id,
                                               body:,
                                               attachmentId: attachment_id,
                                               clientMutationId: 'foo'
                                             }))
  end

  def self.handle_errors(result)
    throw "Unable to send message on dossier #{result.errors.map(&:message).join(',')}" if result.errors.present?
  end

  def self.file_already_posted(dossier_number, filename)
    result = MesDemarches::Client.query(Query::Dossier, variables: { dossier: dossier_number })
    return false if result.errors.present? || result.data.blank?

    result.data&.dossier&.messages&.any? { |m| m&.attachment&.filename == filename }
  end

  Query = MesDemarches::Client.parse <<-'QUERY'
    query Dossier($dossier: Int!) {
      dossier(number: $dossier) {
        messages {
          attachment {
            filename
          }
        }
      }
    }
  QUERY

  Mutation = MesDemarches::Client.parse <<-'GRAPHQL'
    mutation EnvoyerMessage($dossierId: ID!, $instructeurId: ID!, $body: String!, $clientMutationId: String!) {
        dossierEnvoyerMessage(
            input: {
                dossierId: $dossierId,
                instructeurId: $instructeurId,
                body: $body,
                clientMutationId: $clientMutationId
            }) {
            clientMutationId
            errors {
                message
            }
        }
    }

    mutation EnvoyerMessageAvecFichier($dossierId: ID!, $instructeurId: ID!, $body: String!, $attachmentId: ID!, $clientMutationId: String!) {
        dossierEnvoyerMessage(
            input: {
                dossierId: $dossierId,
                instructeurId: $instructeurId,
                body: $body,
                attachment: $attachmentId,
                clientMutationId: $clientMutationId
            }) {
            clientMutationId
            errors {
                message
            }
        }
    }
  GRAPHQL
end
