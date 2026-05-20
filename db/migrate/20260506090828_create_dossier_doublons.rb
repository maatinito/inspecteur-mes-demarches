# frozen_string_literal: true

class CreateDossierDoublons < ActiveRecord::Migration[6.1]
  def change
    create_table :dossier_doublons do |t|
      t.integer :demarche_id, null: false
      t.integer :dossier_number, null: false
      t.string :cle, null: false
      t.string :state, null: false
      t.datetime :depose_at, null: false

      t.timestamps
    end

    add_index :dossier_doublons, :dossier_number, unique: true
    add_index :dossier_doublons, %i[demarche_id cle depose_at]
  end
end
