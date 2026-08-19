# frozen_string_literal: true

FactoryBot.define do
  factory :value_flags, class: Calculs::ValueFlags do
    champ { 'Couverture maladie par l\'organisme d\'accueil' }
    valeurs do
      {
        'Oui' => 'reponse_couverture_maladie_oui',
        'Non' => 'reponse_couverture_maladie_non',
        'Je ne sais pas' => 'reponse_couverture_maladie_incertaine'
      }
    end

    initialize_with { Calculs::ValueFlags.new(attributes) }
  end
end
