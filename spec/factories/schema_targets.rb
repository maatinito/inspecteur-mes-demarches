# frozen_string_literal: true

# == Schema Information
#
# Table name: schema_targets
#
#  id                            :bigint           not null, primary key
#  excluded_block_descriptor_ids :jsonb            not null
#  excluded_field_ids            :jsonb            not null
#  last_synced_at                :datetime
#  target_type                   :string           not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  application_external_id       :string
#  avis_table_external_id        :string
#  demarche_id                   :bigint           not null
#  main_table_external_id        :string
#  workspace_external_id         :string
#
# Indexes
#
#  index_schema_targets_on_demarche_id                  (demarche_id)
#  index_schema_targets_on_demarche_id_and_target_type  (demarche_id,target_type) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (demarche_id => demarches.id)
#
FactoryBot.define do
  factory :schema_target do
    association :demarche
    target_type { 'baserow' }
    workspace_external_id { '42' }
    application_external_id { '17' }
    main_table_external_id { '101' }
  end
end
