# frozen_string_literal: true

class MigrateScheduledTaskRunAtToTimestamp < ActiveRecord::Migration[6.1]
  def self.up
    change_table :scheduled_tasks do |t|
      t.change :run_at, :datetime
    end
  end

  def self.down
    change_table :scheduled_tasks do |t|
      t.change :run_at, :date
    end
  end
end
