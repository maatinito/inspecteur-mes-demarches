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
  def self.enqueue(dossier, task, parameters, run_at)
    task = task.is_a?(Class) ? task.name.underscore : task.to_s
    parameters = parameters.to_json
    query = { dossier:, task:, run_at: }
    record = ScheduledTask.where(query).first
    if record
      record.update(parameters:)
    else
      ScheduledTask.create(query.merge(parameters:))
    end
  end

  def self.clear(task:, dossier:)
    ScheduledTask.where(task:, dossier:).destroy_all
  end
end
