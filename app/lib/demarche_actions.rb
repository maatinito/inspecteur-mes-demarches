# frozen_string_literal: true

class DemarcheActions
  EPOCH = Time.zone.parse('2000-01-01 00:00')

  def self.get_demarche(demarche_number, configuration_name, instructeur_email = nil)
    gql_demarche = get_graphql_demarche(demarche_number)
    demarche = update_or_create_demarche(gql_demarche, configuration_name, instructeur_email)
    update_instructeurs(demarche, gql_demarche)
    demarche
  end

  def self.ping
    MesDemarches.query(MesDemarches::Queries::Ping)
    true
  rescue StandardError => e
    Rails.logger.info("Mes-Démarche seems not accessible : #{e.message}")
    false
  end

  def self.get_graphql_demarche(demarche_number)
    result = MesDemarches.query(MesDemarches::Queries::Demarche,
                                variables: { demarche: demarche_number })

    raise StandardError, result.errors.messages.values.join(',') if result.errors.present?
    raise StandardError, "La démarche #{demarche_number} n'existe pas" if result&.data&.demarche.nil?

    result.data.demarche
  end

  def self.update_or_create_demarche(gql_demarche, configuration_name, instructeur_email)
    gql_instructeur = if instructeur_email
                        gql_demarche.groupe_instructeurs.flat_map(&:instructeurs).find { |i| i.email == instructeur_email }
                      else
                        gql_demarche.groupe_instructeurs.first.instructeurs.first
                      end
    raise StandardError, "Aucun instructeur #{instructeur_email} sur la demarche #{gql_demarche.number}" if gql_instructeur.nil?

    demarche = Demarche.find_or_create_by({ id: gql_demarche.number }) do |d|
      d.checked_at = EPOCH
    end
    demarche.update({
                      libelle: gql_demarche.title,
                      configuration: configuration_name,
                      instructeur: gql_instructeur.id
                    })
    demarche
  end

  def self.update_instructeurs(demarche, gql_demarche)
    instructeurs = User.where(email: gql_demarche.groupe_instructeurs.flat_map(&:instructeurs).map(&:email))
    demarche.instructeurs = instructeurs
  end
end
