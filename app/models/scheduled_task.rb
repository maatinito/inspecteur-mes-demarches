# frozen_string_literal: true

# == Schema Information
#
# Table name: scheduled_tasks
#
#  id         :bigint           not null, primary key
#  dossier    :integer
#  parameters :text
#  run_at     :datetime
#  task       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  by_date     (run_at)
#  st_unicity  (dossier,task,run_at) UNIQUE
#
class ScheduledTask < ApplicationRecord
  def self.enqueue(dossier_number, task, parameters, run_at)
    task_name = task.is_a?(Class) ? task.name.underscore : task.to_s
    ScheduledTask.create(dossier: dossier_number, task: task_name, parameters: parameters.to_json, run_at:)
  end

  def self.clear(task:, dossier_number:)
    ScheduledTask.where(task:, dossier: dossier_number).destroy_all
  end
end
