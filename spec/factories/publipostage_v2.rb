# frozen_string_literal: true

FactoryBot.define do
  factory :publipostage_v2, class: PublipostageV2 do
    etat_du_dossier { 'en_construction' }
    message { 'message {number}' }
    modele { 'spec/fixtures/publipostage_v2.docx' }
    nom_fichier_lot { 'publipostage {number} {horodatage}-{lot}' }
    nom_fichier { 'publipostage v2 {number}' }
    champs { ['Navire', "Date d'arrivée", 'Produits 1', 'Produits 2'] }

    trait :docx do
      type_de_document { 'docx' }
    end

    trait :store_to_field do
      champ_cible { 'publipostage' }
    end

    trait :model_with_errors do
      modele { 'spec/fixtures/publipostage_v2_with_errors.docx' }
    end

    initialize_with { PublipostageV2.new(attributes) }
  end
end
