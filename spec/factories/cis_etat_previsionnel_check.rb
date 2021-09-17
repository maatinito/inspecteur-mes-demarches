# frozen_string_literal: true

FactoryBot.define do
  factory :cis_etat_previsionnel_check, class: Cis::EtatPrevisionnelCheck do
    champ { 'État nominatif des demandeurs' }
    message_champ_non_renseigne { 'message_champ_non_renseigne' }
    message_type_de_fichier { 'message_type_de_fichier' }
    message_colonnes_manquantes { 'message_colonnes_manquantes' }
    message_format_dn { 'message_format_dn' }
    message_format_date_de_naissance { 'message_format_date_de_naissance' }
    message_nom_invalide { 'message_nom_invalide' }
    message_prenom_invalide { 'message_prenom_invalide' }
    message_date_de_naissance { 'message_date_de_naissance' }
    message_dn { 'message_dn' }
    message_colonnes_vides { 'message_colonnes_vides' }
    message_cis_demandes { 'message_cis_demandes' }
    message_age { 'message_age' }
    initialize_with { Cis::EtatPrevisionnelCheck.new(attributes) }
  end
end
