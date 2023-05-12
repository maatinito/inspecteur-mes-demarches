# frozen_string_literal: true

FactoryBot.define do
  factory :act_copy_amount, class: Daf::ActCopyAmount do
    champ_montant { 'Montant à payer' }
    champ_montant_theorique { 'Montant théorique' }
    champ_commande_prete { 'Recherche terminée' }
    champ_commande_gratuite { 'Administration' }
    champ_administration_gratuite { 'Paiement administratif' }

    initialize_with { Daf::ActCopyAmount.new(attributes) }
  end
end
