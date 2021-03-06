# frozen_string_literal: true

class DossierPasserEnInstruction < DossierChangerEtat
  Queries = MesDemarches::Client.parse <<-'GRAPHQL'
    mutation EnInstruction($dossierId: ID!, $instructeurId: ID!, $clientMutationId: String) {
      dossierPasserEnInstruction(input: {
        dossierId: $dossierId,
        instructeurId: $instructeurId,
        clientMutationId: $clientMutationId,
      }) {
        clientMutationId
        dossier {
          id
          number
          state
        }
        errors
      }
    }
  GRAPHQL

  def change_state(demarche, dossier)
    result = MesDemarches::Client.query(Queries::EnInstruction, variables:
      {
        dossierId: dossier.id,
        instructeurId: demarche.instructeur
      })
    throw StandardError.new result.errors if result.errors.present?
  end
end
