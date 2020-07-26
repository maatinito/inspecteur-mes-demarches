# frozen_string_literal: true

FactoryBot.define do
  factory :dossier, class: Hash do
    state { 'en_construction' }
    initialize_with { attributes }
  end
end
