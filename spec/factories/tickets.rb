# frozen_string_literal: true

FactoryBot.define do
  factory :tickets, class: 'Tftn::Tickets' do
    id_table_cours { '42' }
    champ_cours { 'cours' }
    prix_seance { '1500' }
    annotation_montant { 'Montant à payer' }
    annotation_message_usager { 'Message explicatif' }
    states { %w[en_instruction accepte] }

    initialize_with { new(attributes) }
  end
end
