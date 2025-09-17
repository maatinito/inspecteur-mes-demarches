# frozen_string_literal: true

class SendMessage
  def self.deliver_message(dossier, instructeur_id, body, check_not_sent: false) # rubocop:disable Naming/PredicateMethod
    return false if check_not_sent && already_posted(dossier.number, body)

    handle_errors(MesDemarches.query(Mutation::EnvoyerMessage,
                                     variables: {
                                       dossierId: dossier.id,
                                       instructeurId: instructeur_id,
                                       body:,
                                       clientMutationId: 'foo'
                                     }))
    true
  end

  def self.deliver_message_with_file(dossier, instructeur_id, body, file_path, filename, check_not_sent: false) # rubocop:disable Naming/PredicateMethod
    return false if check_not_sent && already_posted(dossier.number, body)

    attachment_id = FileUpload.upload_file(dossier.id, file_path, filename)
    handle_errors(MesDemarches.query(Mutation::EnvoyerMessageAvecFichier,
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
    raise "Unable to send message on dossier #{result.errors.map(&:message).join(',')}" if result.errors.present?
  end

  def self.already_posted(dossier_number, body)
    result = MesDemarches.query(Query::Dossier, variables: { dossier: dossier_number })
    raise "Unable to get dossier nb #{dossier_number}" if result.errors.present? || result.data.blank?

    result.data&.dossier&.messages&.any? { |m| m&.body == body } # rubocop:disable Style/SafeNavigationChainLength
  end

  Query = MesDemarches::Client.parse <<-QUERY
    query Dossier($dossier: Int!) {
      dossier(number: $dossier) {
        messages {
          body
        }
      }
    }
  QUERY

  Mutation = MesDemarches::Client.parse <<-GRAPHQL
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
