# frozen_string_literal: true

class AddReferentielToSchemaTargets < ActiveRecord::Migration[7.2]
  def change
    add_column :schema_targets, :referentiel, :string, default: 'archive', null: false
  end
end
