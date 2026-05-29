# frozen_string_literal: true

FactoryBot.define do
  factory :schema_block_target do
    association :schema_target
    block_descriptor_id { 'main' }
    backend_table_id { '101' }
  end
end
