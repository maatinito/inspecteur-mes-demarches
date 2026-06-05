# frozen_string_literal: true

# == Schema Information
#
# Table name: schema_block_targets
#
#  id                  :bigint           not null, primary key
#  excluded_field_ids  :jsonb            not null
#  last_synced_at      :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  backend_table_id    :string
#  block_descriptor_id :string           not null
#  schema_target_id    :bigint           not null
#
# Indexes
#
#  idx_schema_block_targets_unique                 (schema_target_id,block_descriptor_id) UNIQUE
#  index_schema_block_targets_on_schema_target_id  (schema_target_id)
#
# Foreign Keys
#
#  fk_rails_...  (schema_target_id => schema_targets.id)
#
FactoryBot.define do
  factory :schema_block_target do
    association :schema_target
    block_descriptor_id { 'main' }
    backend_table_id { '101' }
  end
end
