# frozen_string_literal: true

class DossierAccepter < DossierChangerEtat
  attr_accessor :motivation

  def initialize(params)
    super
    @motivation = @params[:motivation] || ''
  end

  def change_state(demarche, dossier)
    result = MesDemarches::Client.query(Queries::Accepter, variables:
      {
        dossierId: dossier.id,
        instructeurId: instructeur_id_for(demarche, dossier),
        motivation:
      })
    throw StandardError.new result.errors if result.errors.present?
  end

  def authorized_fields
    super + %i[motivation]
  end

  Queries = MesDemarches::Client.parse <<-'GRAPHQL'
    mutation Accepter($dossierId: ID!, $instructeurId: ID!, $motivation: String!) {
      dossierAccepter(input: {
        dossierId: $dossierId,
        instructeurId: $instructeurId,
        motivation: $motivation,
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
end
