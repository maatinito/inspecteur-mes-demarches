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
FactoryBot.define do
  factory :scheduled_task do
    dossier { 1 }
    task { 'MyString' }
    parameters { 'MyText' }
    run_at { '2022-03-11' }
  end
end
