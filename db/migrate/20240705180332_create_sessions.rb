# frozen_string_literal: true

class CreateSessions < ActiveRecord::Migration[6.1]
  def change
    create_table :sessions do |t|
      t.string :name
      t.datetime :date
      t.integer :capacity
      t.integer :bookings_count, default: 0, null: false

      t.timestamps
    end

    add_index :sessions, %i[name date], unique: true
  end
end
