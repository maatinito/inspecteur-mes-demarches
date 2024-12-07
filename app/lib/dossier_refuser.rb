# frozen_string_literal: true

class DossierRefuser < DossierChangerEtat
  attr_writer :motivation

  def initialize(params)
    super
    @motivation = @params[:motivation]
  end

  def motivation
    raise StandardError, 'Aucune motivation indiqué pour le classement sans suite' unless @motivation.present?

    @motivation
  end

  def change_state(demarche, dossier)
    case dossier.state
    when 'en_instruction', 'en_construction'
      passer_en_instruction(demarche, dossier) if dossier.state == 'en_construction'
      Rails.logger.info('Refus du dossier')
      result = MesDemarches.query(Queries::Refuser, variables:
        {
          dossierId: dossier.id,
          instructeurId: instructeur_id_for(demarche, dossier),
          motivation:
        })
      raise StandardError, result.errors if result.errors.present?
    when 'refuse'
      Rails.logger.info('Dossier ignoré car déjà classé sans suite')
    else
      Rails.logger.info("Impossible de refuser un dossier déjà cloturé #{dossier.state}")
    end
  end

  def required_fields
    super + %i[motivation]
  end

  Queries = MesDemarches::Client.parse <<-GRAPHQL
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
