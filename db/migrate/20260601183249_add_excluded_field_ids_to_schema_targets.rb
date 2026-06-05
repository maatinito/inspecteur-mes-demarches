# frozen_string_literal: true

class AddExcludedFieldIdsToSchemaTargets < ActiveRecord::Migration[7.2]
  def change
    add_column :schema_targets, :excluded_field_ids, :jsonb, default: [], null: false
    add_column :schema_targets, :excluded_block_descriptor_ids, :jsonb, default: [], null: false
  end
end
