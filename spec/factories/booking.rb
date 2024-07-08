# frozen_string_literal: true

FactoryBot.define do
  factory :booking do
    association :session
    dossier { 1 }
    user { 'user' }
  end
end
