# frozen_string_literal: true

FactoryBot.define do
  factory :excel_from_repetitions, class: Excel::FromRepetitions do
    champs_sources { ['Liste des produits'] }
    champ_cible { 'Produits' }
    modele { 'spec/fixtures/excel_from_repetitions.xlsx' }
    nom_fichier { 'permis {horodatage}' }
    cellule_de_depart { 'B4' }

    trait :model_unknown do
      modele { 'excel_from_repetitions.xlsx' }
    end

    initialize_with { Excel::FromRepetitions.new(attributes) }
  end
end
