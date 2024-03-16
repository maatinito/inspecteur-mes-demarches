# frozen_string_literal: true

FactoryBot.define do
  factory :repetition_count, class: Calculs::RepetitionCount do
    initialize_with { Calculs::RepetitionCount.new({}) }
  end
end
