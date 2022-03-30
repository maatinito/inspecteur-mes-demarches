# frozen_string_literal: true

FactoryBot.define do
  factory :cis_etat_reel_v2_check, class: Cis::EtatReelV2Check do
    champ { 'Relevé des absences' }
    champ_candidats_admis { 'Candidats admis' }
    champ_periode { 'Année' }

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
    message_absence { 'message_absence' }
    message_personnes_inconnues { 'message_personnes_inconnues' }
    message_personnes_manquantes { 'message_personnes_manquantes' }
    message_periode { 'message_periode' }

    initialize_with { Cis::EtatReelV2Check.new(attributes) }
  end
end
