# frozen_string_literal: true

class CreateSuppressionsEnAttente < ActiveRecord::Migration[7.2]
  def change
    create_table :suppressions_en_attente do |t|
      t.bigint :demarche_id, null: false
      t.integer :dossier, null: false
      t.timestamps
    end
    add_index :suppressions_en_attente, %i[demarche_id dossier], unique: true
  end
end
