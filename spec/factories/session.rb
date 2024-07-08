# frozen_string_literal: true

FactoryBot.define do
  factory :session do
    #  capacity       :integer
    #  date           :datetime
    #  name           :string

    capacity { 1 }
    date { Time.zone.parse('2024-07-26') }
    name { 'Jentreprends' }
  end
end
