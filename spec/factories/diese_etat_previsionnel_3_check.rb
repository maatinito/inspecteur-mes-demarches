# frozen_string_literal: true

FactoryBot.define do
  factory :diese_etat_previsionnel_3_check, class: Diese::EtatPrevisionnelCheck do
    champ { 'Etat nominatif des salariés' }
    message_type_de_fichier { 'message_type_de_fichier' }
    message_colonnes_manquantes { 'message_colonnes_manquantes' }
    message_colonnes_vides { 'message_colonnes_vides' }
    message_format_dn { 'message_format_dn' }
    message_format_date_de_naissance { 'message_format_date_de_naissance' }
    message_dn { 'message_dn' }
    message_date_de_naissance { 'message_date_de_naissance' }
    message_nom_invalide { 'message_nom_invalide' }
    message_prenom_invalide { 'message_prenom_invalide' }
    message_champ_non_renseigne { 'message_champ_non_renseigne' }
    message_different_value { 'message_different_value' }
    message_taux_depasse { 'message_taux_depasse' }

    initialize_with { Diese::EtatPrevisionnel3Check.new(attributes) }
  end
end
