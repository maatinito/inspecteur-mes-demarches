# frozen_string_literal: true

class CreateChecks < ActiveRecord::Migration[5.2]
  def change
    create_table :checks do |t|
      t.integer :dossier
      t.string :checker

      t.timestamps
    end
    add_index :checks, :dossier, name: 'by_dossier'
    add_index :checks, %i[dossier checker], name: 'unicity', unique: true
  end
end
