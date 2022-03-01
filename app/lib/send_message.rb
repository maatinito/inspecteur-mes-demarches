class SendMessage
  def self.send(dossier_id, instructeur_id, body)
    handleErrors(MesDemarches::Client.query(Mutation::EnvoyerMessage,
                                            variables: {
                                              dossierId: dossier_id,
                                              instructeurId: instructeur_id,
                                              body: body,
                                              clientMutationId: 'foo'
                                            }))

  end

  def self.send_with_file(dossier_id, instructeur_id, body, file_path, filename)
    attachment_id = FileUpload.upload_file(dossier_id, file_path, filename)
    handleErrors(MesDemarches::Client.query(Mutation::EnvoyerMessageAvecFichier,
                                            variables: {
                                              dossierId: dossier_id,
                                              instructeurId: instructeur_id,
                                              body: body,
                                              attachment: attachment_id,
                                              clientMutationId: 'foo'
                                            }))
  end

  private

  def self.handleErrors(result)
    throw "Unable to send message on dossier #{dossier_id} #{result.errors.messages.values.join(',')}" if result.errors.present?
  end

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
