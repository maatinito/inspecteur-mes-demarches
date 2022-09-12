# frozen_string_literal: true

FactoryBot.define do
  factory :payment_order, class: Payzen::PaymentOrder do
    etat_du_dossier { 'en_instruction' }
    mode_test { 'oui' }
    reference { 'reference' }
    champ_montant { 'Montant à payer' }
    champ_ordre_de_paiement { 'Demande de paiement' }
    message { 'message' }

    initialize_with { Payzen::PaymentOrder.new(attributes) }
  end
end
