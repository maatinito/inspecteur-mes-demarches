# frozen_string_literal: true

# == Schema Information
#
# Table name: schema_targets
#
#  id                            :bigint           not null, primary key
#  excluded_block_descriptor_ids :jsonb            not null
#  excluded_field_ids            :jsonb            not null
#  last_synced_at                :datetime
#  target_type                   :string           not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  application_external_id       :string
#  avis_table_external_id        :string
#  demarche_id                   :bigint           not null
#  main_table_external_id        :string
#  workspace_external_id         :string
#
# Indexes
#
#  index_schema_targets_on_demarche_id                  (demarche_id)
#  index_schema_targets_on_demarche_id_and_target_type  (demarche_id,target_type) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (demarche_id => demarches.id)
#
class SchemaTarget < ApplicationRecord
  belongs_to :demarche
  has_many :schema_block_targets, dependent: :destroy

  enum :target_type, { baserow: 'baserow', grist: 'grist' }, validate: true

  validates :demarche_id, uniqueness: { scope: :target_type }

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

  def block_excluded?(block_id)
    excluded_block_descriptor_ids.include?(block_id.to_s)
  end

  def exclude_block!(block_id)
    return if block_excluded?(block_id)

    update!(excluded_block_descriptor_ids: excluded_block_descriptor_ids + [block_id.to_s])
  end

  def include_block!(block_id)
    return unless block_excluded?(block_id)

    update!(excluded_block_descriptor_ids: excluded_block_descriptor_ids - [block_id.to_s])
  end
end
