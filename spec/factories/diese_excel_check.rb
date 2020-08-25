# frozen_string_literal: true

FactoryBot.define do
  factory :diese_excel_check, class: Diese::ExcelCheck do
    champ { 'Etat nominatif des salariés' }
    message_type_de_fichier { 'message_type_de_fichier' }
    message_colonnes_manquantes { 'message_colonnes_manquantes' }
    message_format_dn { 'message_format_dn' }
    message_format_date_de_naissance { 'message_format_date_de_naissance' }
    message_dn { 'message_dn' }
    message_date_de_naissance { 'message_date_de_naissance' }
    message_nom_invalide { 'message_nom_invalide' }
    message_prenom_invalide { 'message_prenom_invalide' }
    message_champ_non_renseigne { 'message_champ_non_renseigne' }
    message_different_value { 'message_different_value' }

    initialize_with { Diese::ExcelCheck.new(attributes) }
  end
end
