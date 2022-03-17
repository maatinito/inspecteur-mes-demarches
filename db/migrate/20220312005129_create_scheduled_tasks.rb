# frozen_string_literal: true

class CreateScheduledTasks < ActiveRecord::Migration[6.1]
  def change
    create_table :scheduled_tasks do |t|
      t.integer :dossier
      t.string :task
      t.text :parameters
      t.date :run_at

      t.timestamps
    end
    add_index :scheduled_tasks, %i[run_at], name: 'by_date'
    add_index :scheduled_tasks, %i[dossier task run_at], name: 'st_unicity', unique: true
  end
end
