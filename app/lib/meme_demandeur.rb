# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'

class MemeDemandeur < FieldChecker
  def initialize(params)
    super(params)
  end

  def version
    10
  end

  def required_fields
    %i[champ message_mauvais_demandeur]
  end

  def authorized_fields
    %i[champ_cible message_mauvaise_demarche verifier_usager message_mauvais_usager]
  end

  Queries = MesDemarches::Client.parse <<-'GRAPHQL'
    query Instructeurs($demarche : Int!) {
      demarche(number: $demarche) {
        groupeInstructeurs {
          instructeurs {
            email
          }
        }
      }
    }

    query Dossier($dossier: Int!) {
      dossier(number: $dossier) {
          usager {
            email
          }
          demandeur {
            ... on PersonneMorale {
              siret
            }
            ... on PersonnePhysique {
              nom
              prenom
            }
          }
          champs {
            label
          }
        }
      }
  GRAPHQL

  def instructeurs
    @instructeurs ||= load_instructeurs
  end

  def load_instructeurs
    response = MesDemarches::Client.query(Queries::Instructeurs, variables: { demarche: @demarche.id })
    return Set[] unless (data = response.data)

    data.demarche.groupe_instructeurs.map do |group|
      group.instructeurs.map(&:email)
    end.flatten
  end

  def check(dossier)
    champs = field(dossier, @params[:champ])
    if champs.present?
      champs.each do |champ|
        dossier_siret = dossier&.demandeur&.siret
        dossier_number = champ.string_value&.to_i
        response = MesDemarches::Client.query(Queries::Dossier,
                                              variables: { dossier: dossier_number })
        unless (data = response.data)
          add_message(@params[:champ], dossier_siret, "Le dossier #{dossier_number} est introuvable")
          return
        end

        target_dossier = data.dossier
        field_siret = target_dossier&.demandeur&.siret
        if dossier_siret != field_siret
          add_message(@params[:champ], dossier_number, @params[:message_mauvais_demandeur] + ':' + dossier_siret)
        end
        champ_cible = @params[:champ_cible]
        if champ_cible.present?
          unless field(target_dossier, champ_cible).present?
            add_message(@params[:champ], dossier_number, @params[:message_mauvaise_demarche])
          end
        end
        next unless @params[:verifier_usager].present?

        current_user = dossier&.usager&.email
        target_user = target_dossier&.usager.email
        # ignore check if a user is also an instructor
        next if instructeurs.include?(current_user) || instructeurs.include?(target_user)

        add_message(@params[:champ], dossier_number, @params[:message_mauvais_usager]) if current_user != target_user
      end
    end
  end
end
