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

    trait :model_with_errors do
      modele { 'spec/fixtures/publipostage_with_errors.docx' }
    end

    trait :on_repetition do
      champ_source { 'Bloc' }
      champ_cible { 'Publipostage' }
      champs { ['Navire', "Date d'arrivée", 'Motif'] }
    end

    initialize_with { Publipostage.new(attributes) }
  end
end
