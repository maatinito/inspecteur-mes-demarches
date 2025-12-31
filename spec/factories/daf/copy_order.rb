# frozen_string_literal: true

FactoryBot.define do
  factory :copy_order, class: Daf::CopyOrder do
    champ_source { 'Bloc source' }
    bloc_destination { 'Bloc destination' }
    champ_destination { 'Champ cible' }
    valeur { '{Champ1}' }

    initialize_with { Daf::CopyOrder.new(attributes) }

    trait :with_multiple_fields do
      champ_destination { nil }
      valeur { nil }
      champs_destination do
        {
          'Champ texte 1' => '{Source 1}',
          'Champ texte 2' => 'Source directe'
        }
      end
    end

    trait :with_file_fields do
      champ_destination { nil }
      valeur { nil }
      champs_destination do
        {
          'Champ texte' => '{Nom produit}',
          'Fichier destination' => 'Fichier source'
        }
      end
    end
  end
end
