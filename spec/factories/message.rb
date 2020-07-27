# frozen_string_literal: true

FactoryBot.define do
  factory :message do
    association :check
    message { 'message' }
    field { 'field' }
    value { 'value' }
  end
end
