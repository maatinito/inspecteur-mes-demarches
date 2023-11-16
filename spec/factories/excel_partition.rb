# frozen_string_literal: true

FactoryBot.define do
  factory :excel_partition, class: Excel::Partition do
    variable { 'my_array' }
    colonne { 'k1' }

    initialize_with { Excel::Partition.new(attributes) }
  end
end
