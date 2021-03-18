# frozen_string_literal: true

FactoryBot.define do
  factory :regex_check do
    message { 'message_regex_check' }
    regex { '[0-9]+' }

    trait :for_no_tahiti_iti do
      champ { 'Numéro Tahiti ITI' }
      regex { '[A-Z0-9][0-9]{8}' }
      message_aide { 'message_aide' }
      regex_aide { '[^A-Z0-9]' }
    end

    initialize_with do
      object = RegexCheck.new(attributes)
      object.demarche = DemarcheActions.get_demarche(871, 'DiESE', 'clautier@idt.pf')
      object
    end
  end
end
