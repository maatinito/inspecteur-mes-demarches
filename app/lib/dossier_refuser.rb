# frozen_string_literal: true

class DossierRefuser < DossierChangerEtat
  attr_writer :motivation

  def initialize(params)
    super
    @motivation = @params[:motivation]
  end

  def motivation
    throw StandardError.new 'Aucune motivation indiqué pour le classement sans suite' unless @motivation.present?
    @motivation
  end

  def change_state(demarche, dossier)
    result = MesDemarches::Client.query(Queries::Refuser, variables:
      {
        dossierId: dossier.id,
        instructeurId: instructeur_id_for(demarche, dossier),
        motivation:
      })
    pp result.errors
  end

  def required_fields
    super + %i[motivation]
  end

  Queries = MesDemarches::Client.parse <<-'GRAPHQL'
    mutation Refuser($dossierId: ID!, $instructeurId: ID!, $motivation: String!) {
      dossierRefuser(input: {
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
