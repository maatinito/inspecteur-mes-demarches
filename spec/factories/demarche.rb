# frozen_string_literal: true

FactoryBot.define do
  factory :demarche do
    libelle { 'demarche' }
    checked_at { Time.zone.now }
    instructeur { 'hijun' }
    configuration { 'configuration' }
  end
end
