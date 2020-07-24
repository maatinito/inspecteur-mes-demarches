# frozen_string_literal: true

class AddCronToDelayedJobs < ActiveRecord::Migration[5.2]
  def self.up
    add_column :delayed_jobs, :cron, :string
  end

  def self.down
    remove_column :delayed_jobs, :cron
  end
end
