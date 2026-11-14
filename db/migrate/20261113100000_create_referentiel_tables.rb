# frozen_string_literal: true

class CreateReferentielTables < ActiveRecord::Migration[7.2]
  def change
    create_table :referentiel_tables do |t|
      t.string :backend, null: false
      t.string :table_ref, null: false
      t.string :mode, null: false
      t.bigint :proprietaire
      t.datetime :refus_depuis
      t.datetime :alerte_le
      t.timestamps
    end
    add_index :referentiel_tables, %i[backend table_ref], unique: true
  end
end
