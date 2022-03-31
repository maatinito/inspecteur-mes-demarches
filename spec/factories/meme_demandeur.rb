# frozen_string_literal: true

FactoryBot.define do
  factory :meme_demandeur do
    champ { 'Numéro dossier CSE' }
    champ_cible { ['Effectif M-1'] }
    verifier_usager { true }
    message_mauvaise_demarche { 'message_mauvaise_demarche' }
    message_mauvais_demandeur { 'message_mauvais_demandeur' }
    message_mauvais_usager { 'message_mauvais_usager' }

    initialize_with { MemeDemandeur.new(attributes) }
  end
end
