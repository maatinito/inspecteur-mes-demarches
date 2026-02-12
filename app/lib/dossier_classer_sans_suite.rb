# frozen_string_literal: true

class DossierClasserSansSuite < DossierChangerEtat
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
      Rails.logger.info('Classement sans suite du dossier')
      result = MesDemarches.query(Queries::ClasserSansSuite, variables:
        {
          dossierId: dossier.id,
          instructeurId: instructeur_id_for(demarche, dossier),
          motivation:
        })
      raise StandardError, result.errors.messages.values.join(', ') if result.errors.present?
    when 'sans_suite'
      Rails.logger.info('Dossier ignoré car déjà classé sans suite')
    else
      Rails.logger.info("Impossible d'accepter un dossier déjà cloturé #{dossier.state}")
    end
  end

  def required_fields
    super + %i[motivation]
  end

  Queries = MesDemarches::Client.parse <<-GRAPHQL
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
