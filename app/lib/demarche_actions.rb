# frozen_string_literal: true

class DemarcheActions
  EPOCH = Time.zone.parse('2000-01-01 00:00')

  def self.get_demarche(demarche_number, configuration_name, instructeur_email)
    result = MesDemarches::Client.query(MesDemarches::Queries::Demarche,
                                        variables: { demarche: demarche_number })
    throw StandardError.new result.errors.join(',') if result.errors.present?
    throw StandardError.new "La démarche #{demarche_number} n'existe pas" if result.data.demarche.nil?

    gql_demarche = result.data.demarche
    gql_instructeur = gql_demarche.groupe_instructeurs.flat_map(&:instructeurs).find { |i| i.email == instructeur_email }
    throw StandardError.new "Aucun instructeur #{@instructeur.email} sur la demarche #{demarche_number}" if gql_instructeur.nil?

    demarche_attributes = {
      id: demarche_number,
      libelle: gql_demarche.title,
      configuration: configuration_name,
      instructeur: gql_instructeur.id
    }
    demarche = Demarche.find_or_create_by(demarche_attributes) do |d|
      d.checked_at = EPOCH
    end
    demarche.save!
    demarche
  end
end
