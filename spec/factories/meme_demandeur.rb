# frozen_string_literal: true

FactoryBot.define do
  factory :meme_demandeur do
    champ { 'Numéro dossier DESETI' }
    champ_cible { ["Cessation totale et temporaire d'activité", "Absence totale d'activité"] }
    verifier_usager { true }
    message_mauvaise_demarche { 'message_mauvaise_demarche' }
    message_mauvais_demandeur { 'message_mauvais_demandeur' }
    message_mauvais_usager { 'message_mauvais_usager' }

    initialize_with do
      meme_demandeur = MemeDemandeur.new(attributes)
      meme_demandeur.demarche = DemarcheActions.get_demarche(217, 'DESETI', "clautier#{64.chr}idt.pf")
      meme_demandeur
    end
  end
end
