# frozen_string_literal: true

FactoryBot.define do
  factory :act_copy_amount, class: Daf::ActCopyAmount do
    champ_montant { 'Montant' }
    champ_commande_prete { 'Recherche terminée' }

    initialize_with { Daf::ActCopyAmount.new(attributes) }
  end
end
