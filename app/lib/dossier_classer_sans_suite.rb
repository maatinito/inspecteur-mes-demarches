# frozen_string_literal: true

class DossierClasserSansSuite < DossierChangerEtat
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
    result = MesDemarches::Client.query(Queries::ClasserSansSuite, variables:
      {
        dossierId: dossier.id,
        instructeurId: instructeur_id_for(demarche, dossier),
        motivation:
      })
    throw StandardError.new result.errors if result.errors.present?
  end

  def required_fields
    super + %i[motivation]
  end

  Queries = MesDemarches::Client.parse <<-'GRAPHQL'
    mutation ClasserSansSuite($dossierId: ID!, $instructeurId: ID!, $motivation: String!) {
      dossierClasserSansSuite(input: {
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
