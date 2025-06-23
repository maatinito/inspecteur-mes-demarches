# frozen_string_literal: true

FactoryBot.define do
  factory :publipostage, class: Publipostage do
    etat_du_dossier { 'en_construction' }
    message { 'message {number}' }
    modele { 'publipostage{VAR}.docx' }
    nom_fichier_lot { 'publipostage {number} {horodatage}-{lot}' }
    nom_fichier { 'publipostage {number}' }
    champs { ['Navire', "Date d'arrivée"] }

    trait :docx do
      type_de_document { 'docx' }
    end

    trait :store_to_field do
      champ_cible { 'publipostage' }
    end

    initialize_with { Publipostage.new(attributes) }
  end
end
