# frozen_string_literal: true

class CreateBookings < ActiveRecord::Migration[6.1]
  def change
    create_table :bookings do |t|
      t.integer :dossier
      t.string :user
      t.references :session

      t.timestamps
    end

    add_index :bookings, %i[dossier user session_id], unique: true
  end
end
