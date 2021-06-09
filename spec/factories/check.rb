# frozen_string_literal: true

FactoryBot.define do
  factory :check do
    association :demarche
    dossier { 1 }
    checker { 'checker' }
    version { 1 }
    failed { false }
    posted { false }

    factory :failed_check do
      failed { true }
    end
    factory :check_with_messages do
      posted { true }
      messages { [association(:message, check: instance)] }
    end
  end
end
