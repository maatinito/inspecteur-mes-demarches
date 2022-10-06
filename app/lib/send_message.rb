# frozen_string_literal: true

class SendMessage
  def self.send(dossier, instructeur_id, body, check_not_sent: false)
    return false if check_not_sent && already_posted(dossier.number, body)

    handle_errors(MesDemarches::Client.query(Mutation::EnvoyerMessage,
                                             variables: {
                                               dossierId: dossier.id,
                                               instructeurId: instructeur_id,
                                               body:,
                                               clientMutationId: 'foo'
                                             }))
    true
  end

  def self.send_with_file(dossier, instructeur_id, body, file_path, filename, check_not_sent: false)
    return false if check_not_sent && already_posted(dossier.number, body)

    attachment_id = FileUpload.upload_file(dossier_id, file_path, filename)
    handle_errors(MesDemarches::Client.query(Mutation::EnvoyerMessageAvecFichier,
                                             variables: {
                                               dossierId: dossier.id,
                                               instructeurId: instructeur_id,
                                               body:,
                                               attachmentId: attachment_id,
                                               clientMutationId: 'foo'
                                             }))
    true
  end

  def self.handle_errors(result)
    throw "Unable to send message on dossier #{result.errors.map(&:message).join(',')}" if result.errors.present?
  end

  def self.already_posted(dossier_number, body)
    result = MesDemarches::Client.query(Query::Dossier, variables: { dossier: dossier_number })
    throw "Unable to get dossier nb #{dossier_number}" if result.errors.present? || result.data.blank?

    result.data&.dossier&.messages&.any? { |m| m&.body == body }
  end

  Query = MesDemarches::Client.parse <<-'QUERY'
    query Dossier($dossier: Int!) {
      dossier(number: $dossier) {
        messages {
          body
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
