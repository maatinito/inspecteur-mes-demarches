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
class SchemaBlockTarget < ApplicationRecord
  belongs_to :schema_target

  validates :block_descriptor_id, presence: true,
                                  uniqueness: { scope: :schema_target_id }

  def field_excluded?(field_id)
    excluded_field_ids.include?(field_id.to_s)
  end

  def exclude_field!(field_id)
    return if field_excluded?(field_id)

    update!(excluded_field_ids: excluded_field_ids + [field_id.to_s])
  end

  def include_field!(field_id)
    return unless field_excluded?(field_id)

    update!(excluded_field_ids: excluded_field_ids - [field_id.to_s])
  end
end
