# frozen_string_literal: true

FactoryBot.define do
  factory :reservation_jentreprends, class: Reservation::Jentreprends do
    etat_du_dossier { 'en_construction' }
    champ_date { 'Date choisie' }
    message_indisponible { 'indisponible' }
    capacite { 1 }

    trait :with_disponibilites do
      message_disponibilites { 'disponibilites {dates}' }
    end

    initialize_with { Reservation::Jentreprends.new(attributes) }
  end
end
