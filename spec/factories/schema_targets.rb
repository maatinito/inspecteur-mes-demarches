# frozen_string_literal: true

FactoryBot.define do
  factory :schema_target do
    association :demarche
    target_type { 'baserow' }
    workspace_external_id { '42' }
    application_external_id { '17' }
    main_table_external_id { '101' }
  end
end
