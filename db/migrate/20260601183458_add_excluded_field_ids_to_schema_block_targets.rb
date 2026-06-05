# frozen_string_literal: true

class AddExcludedFieldIdsToSchemaBlockTargets < ActiveRecord::Migration[7.2]
  def change
    add_column :schema_block_targets, :excluded_field_ids, :jsonb, default: [], null: false
  end
end
