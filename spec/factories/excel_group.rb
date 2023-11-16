# frozen_string_literal: true

FactoryBot.define do
  factory :excel_group, class: Excel::Group do
    variable { 'my_array' }
    colonnes { 'k1,k2' }

    trait :colonnes_as_list do
      colonnes { %w[k1 k2] }
    end

    initialize_with { Excel::Group.new(attributes) }
  end
end
