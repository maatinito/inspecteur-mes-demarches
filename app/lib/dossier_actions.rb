# frozen_string_literal: true

class DossierActions
  EPOCH = Time.zone.parse('2000-01-01 00:00')

  def self.on_dossiers(demarche_id, since)
    cursor = nil
    loop do
      response = MesDemarches::Client.query(MesDemarches::Queries::DossiersModifies,
                                            variables: {
                                              demarche: demarche_id,
                                              since: since.iso8601,
                                              cursor: cursor
                                            })

      unless (data = response.data)
        throw StandardError.new "La démarche #{demarche_number} est introuvable #{ENV['GRAPHQL_HOST']}: #{response.errors.values.join(',')}"
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

  def self.on_dossier(dossier_number)
    result = MesDemarches::Client.query(MesDemarches::Queries::Dossier,
                                        variables: { dossier: dossier_number })
    dossier = result.data&.dossier
    yield dossier if dossier.present?
    Rails.logger.error(result.errors.values.join(',')) unless dossier
  end
end
