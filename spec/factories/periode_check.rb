# frozen_string_literal: true

FactoryBot.define do
  factory :periode_check do
    message { 'message_periode_check' }
    periode { '1..7' }

    trait :for_deseti do
      champ_debut { "Date de début de l'isolement" }
      champ_fin { "Date de fin de l'isolement" }
    end

    trait :for_res do
      champ_debut { 'Liste des salariés.Date de début de la quarantaine' }
      champ_fin { 'Liste des salariés.Date de fin de la quarantaine' }
    end

    initialize_with do
      object = PeriodeCheck.new(attributes)
      object.demarche = DemarcheActions.get_demarche(217, 'DESETI', 'clautier@idt.pf')
      object
    end
  end
end
