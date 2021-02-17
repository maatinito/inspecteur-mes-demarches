# frozen_string_literal: true

FactoryBot.define do
  factory :etat_reel_check, class: Diese::EtatReelCheck do
    champ { 'Etat nominatif actualisé' }
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
    message_secteur_activite { 'message_secteur_activite' }
    initialize_with { Diese::EtatReelCheck.new(attributes) }
  end
end
