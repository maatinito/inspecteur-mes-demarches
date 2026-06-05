# frozen_string_literal: true

class CreateSchemaBlockTargets < ActiveRecord::Migration[7.2]
  def change
    create_table :schema_block_targets do |t|
      t.references :schema_target, null: false, foreign_key: true
      t.string :block_descriptor_id, null: false
      t.string :backend_table_id
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :schema_block_targets, %i[schema_target_id block_descriptor_id], unique: true, name: 'idx_schema_block_targets_unique'
  end
end
