# frozen_string_literal: true

FactoryBot.define do
  factory :reject_invalid_files, class: Daf::RejectInvalidFiles do
    champ { 'Demandes' }
    max { 2 }

    trait :max10 do
      max { 10 }
    end
    initialize_with { Daf::RejectInvalidFiles.new(attributes) }
  end
end
