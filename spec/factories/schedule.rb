# frozen_string_literal: true

FactoryBot.define do
  factory :schedule, class: Schedule do
    etat_du_dossier { 'en_instruction' }
    champ_date_de_reference { 'champ' }
    champ_stockage { 'Rappel' }
    decalage_jours { 0 }
    decalage_heures { 0 }
    heure { '' }

    initialize_with { Schedule.new(attributes) }
  end
end
