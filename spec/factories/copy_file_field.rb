# frozen_string_literal: true

FactoryBot.define do
  factory :copy_file_field, class: CopyFileField do
    etat_du_dossier { 'en_construction' }
    champ_source { 'PV' }
    champ_cible { 'PV Final' }
    nom_fichier { 'PV {number}' }

    trait :with_multiple_fields do
      champ_source { ['PV', 'Liste des marchandises non-conformes'] }
    end

    initialize_with { CopyFileField.new(attributes) }
  end
end
