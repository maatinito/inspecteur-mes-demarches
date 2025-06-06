# frozen_string_literal: true

class DossierAccepter < DossierChangerEtat
  attr_accessor :motivation

  def initialize(params)
    super
    @motivation = @params[:motivation] || ''
  end

  def change_state(demarche, dossier)
    case dossier.state
    when 'en_instruction', 'en_construction'
      passer_en_instruction(demarche, dossier) if dossier.state == 'en_construction'
      Rails.logger.info('Acceptation du dossier')
      result = MesDemarches.query(Queries::Accepter, variables:
        {
          dossierId: dossier.id,
          instructeurId: instructeur_id_for(demarche, dossier),
          motivation:
        })
      raise StandardError, result.errors if result.errors.present?
    when 'accepte'
      Rails.logger.info('Dossier ignoré car déjà accepté')
    else
      Rails.logger.info("Impossible d'accepter un dossier déjà cloturé #{dossier.state}")
    end
  end

  def authorized_fields
    super + %i[motivation]
  end

  Queries = MesDemarches::Client.parse <<-GRAPHQL
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
