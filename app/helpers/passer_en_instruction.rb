class PasserEnInstruction < ChangerEtat
  Queries = MesDemarches::Client.parse <<-'GRAPHQL'
    query Dossier($dossier: Int!) {
      dossier(number: $dossier) {
          id
          state
          datePassageEnConstruction
          datePassageEnInstruction
          dateTraitement
          dateDerniereModification
      }
    }

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

  def initialize(params)
    super
    @conditions = params[:conditions]
  end

  def required_fields
    super
  end

  def authorized_fields
    super + %i[conditions]
  end

  def conditions_ok
    return true
  end

  def change_state
    result = MesDemarches::Client.query(Queries::EnInstruction, variables:
      {
        dossierId: dossier.id,
        instructeurId: @demarche.instructeur,
        clientMutationId: @dossier_number.to_s
      })
    pp result.errors
  end

  def process(demarche, dossier_number)
    @demarche = demarche
    @dossier_number = dossier_number
    @dossier = nil
    change_state if conditions_ok
  end

  def get_dossier(dossier_number)
    response = MesDemarches::Client.query(Queries::Dossier, variables: { dossier: dossier_number })
    data = response.data
    return data&.dossier
  end

  def dossier
    @dossier ||= get_dossier(@dossier_number)
  end
end
