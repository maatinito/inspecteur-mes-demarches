# frozen_string_literal: true

module MesDemarches
  # Récupère les avis d'un dossier Mes-Démarches via GraphQL,
  # avec leurs pièces jointes (attachments).
  #
  # Module partagé entre BaserowSync (synchronisation vers Baserow)
  # et potentiellement AvisToBlocRepetable (refactor ultérieur).
  module AvisFetcher
    # TODO: refactor AvisToBlocRepetable#fetch_avis to delegate to AvisFetcher.fetch
    #       (hors périmètre v1 baserow_sync-avis)
    Query = MesDemarches::Client.parse <<-GRAPHQL
      query DossierAvis($dossier: Int!) {
        dossier(number: $dossier) {
          avis {
            id
            question
            reponse
            questionLabel
            questionAnswer
            dateQuestion
            dateReponse
            expert { id, email }
            claimant { id, email }
            attachments {
              filename
              byteSize
              url
              contentType
            }
          }
        }
      }
    GRAPHQL

    def self.fetch(dossier_number)
      result = MesDemarches.query(Query::DossierAvis, variables: { dossier: dossier_number })

      if result.errors.present?
        Rails.logger.error(
          "AvisFetcher: erreur GraphQL pour dossier #{dossier_number}: " \
          "#{result.errors.map(&:message).join(', ')}"
        )
        return []
      end

      result.data&.dossier&.avis || []
    rescue StandardError => e
      Rails.logger.error("AvisFetcher: exception pour dossier #{dossier_number}: #{e.class}: #{e.message}")
      []
    end
  end
end
