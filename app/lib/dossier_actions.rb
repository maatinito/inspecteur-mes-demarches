# frozen_string_literal: true

class DossierActions
  EPOCH = Time.zone.parse('2000-01-01 00:00')

  def self.on_dossiers(demarche_id, since)
    cursor = nil
    loop do
      response = MesDemarches.query(MesDemarches::Queries::DossiersModifies,
                                    variables: {
                                      demarche: demarche_id,
                                      since: since.iso8601,
                                      cursor:
                                    })

      unless (data = response.data)
        raise StandardError, "La démarche #{demarche_id} est introuvable #{ENV.fetch('GRAPHQL_HOST', nil)}: #{response.errors.values.join(',')}"
      end

      dossiers = data.demarche.dossiers
      dossiers.nodes.each do |dossier|
        yield dossier if dossier.present?
      end
      page_info = dossiers.page_info

      break unless page_info.has_next_page

      cursor = page_info.end_cursor
    end
  end

  # Numéros des dossiers supprimés ou en corbeille depuis `since` (deux flux GraphQL),
  # chacun rendu une seule fois.
  def self.on_deleted_dossiers(demarche_id, since)
    vus = Set.new
    [[MesDemarches::Queries::DossiersEnCorbeille, :pending_deleted_dossiers],
     [MesDemarches::Queries::DossiersSupprimes, :deleted_dossiers]].each do |requete, connexion|
      each_deleted_page(requete, connexion, demarche_id, since) do |number|
        yield number if vus.add?(number)
      end
    end
  end

  def self.each_deleted_page(requete, connexion, demarche_id, since)
    cursor = nil
    loop do
      response = MesDemarches.query(requete, variables: { demarche: demarche_id, since: since.iso8601, cursor: })

      unless (data = response.data)
        raise StandardError, "La démarche #{demarche_id} est introuvable #{ENV.fetch('GRAPHQL_HOST', nil)}: #{response.errors.values.join(',')}"
      end

      dossiers = data.demarche.public_send(connexion)
      dossiers.nodes.each { |node| yield node.number if node.present? }
      page_info = dossiers.page_info

      break unless page_info.has_next_page

      cursor = page_info.end_cursor
    end
  end

  private_class_method :each_deleted_page

  def self.on_dossier(dossier_number)
    response = MesDemarches.query(MesDemarches::Queries::Dossier,
                                  variables: { dossier: dossier_number })
    result = response.data&.dossier
    Rails.logger.error(response.errors.values.join(',')) unless result
    result = yield result if result.present? && block_given?
    result
  end
end
