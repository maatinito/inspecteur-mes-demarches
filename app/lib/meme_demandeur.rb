# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'

class MemeDemandeur < FieldChecker
  def initialize(params)
    super(params)
  end

  def version
    13
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
    throw StandardError.new "Le champ #{@params[:champ]} n'existe pas sur le dossier #{dossier.number}"  if champs.blank?

    champs.each do |champ|
      dossier_siret = dossier&.demandeur&.siret
      dossier_number = champ.string_value&.to_i
      response = MesDemarches::Client.query(Queries::Dossier,
                                            variables: { dossier: dossier_number })
      unless (data = response.data)
        add_message(@params[:champ], dossier_siret, "Le dossier #{dossier_number} est introuvable")
        next
      end

      target_dossier = data.dossier
      check_numero_tahiti(dossier_number, dossier_siret, target_dossier)
      check_target_field(dossier_number, target_dossier)
      check_user_account(dossier, dossier_number, target_dossier) if @params[:verifier_usager].present?
    end
  end

  private

  def check_user_account(dossier, dossier_number, target_dossier)
    current_user = dossier&.usager&.email
    target_user = target_dossier&.usager&.email
    # OK if dossiers are created by same user or if one dossier's author is an instructor
    return if current_user == target_user || instructeurs.include?(current_user) || instructeurs.include?(target_user)

    add_message(@params[:champ], dossier_number, @params[:message_mauvais_usager])
  end

  def check_target_field(dossier_number, target_dossier)
    champ_cible = @params[:champ_cible]
    return if champ_cible.blank? || field(target_dossier, champ_cible).present?

    add_message(@params[:champ], dossier_number, @params[:message_mauvaise_demarche])
  end

  def check_numero_tahiti(dossier_number, dossier_siret, target_dossier)
    field_siret = target_dossier&.demandeur&.siret
    add_message(@params[:champ], dossier_number, @params[:message_mauvais_demandeur] + ':' + dossier_siret) if dossier_siret != field_siret
  end
end
