# frozen_string_literal: true

class CreateDossierData < ActiveRecord::Migration[6.1]
  def change
    create_table :dossier_data do |t|
      t.integer :dossier, null: false
      t.string :label, null: false
      t.jsonb :data, null: false # Utilisation de JSONB pour PostgreSQL

      t.timestamps
    end

    # Ajout d'un index unique pour éviter les doublons
    add_index :dossier_data, %i[dossier label], unique: true
  end
end
