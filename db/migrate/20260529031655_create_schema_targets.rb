# frozen_string_literal: true

class CreateSchemaTargets < ActiveRecord::Migration[7.2]
  def change
    create_table :schema_targets do |t|
      t.references :demarche, null: false, foreign_key: true
      t.string :target_type, null: false
      t.string :workspace_external_id
      t.string :application_external_id
      t.string :main_table_external_id
      t.string :avis_table_external_id
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :schema_targets, %i[demarche_id target_type], unique: true
  end
end
