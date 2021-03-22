# frozen_string_literal: true

# == Schema Information
#
# Table name: syncs
#
#  id         :bigint           not null, primary key
#  job        :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
FactoryBot.define do
  factory :sync do
    job { 'MyString' }
  end
end
