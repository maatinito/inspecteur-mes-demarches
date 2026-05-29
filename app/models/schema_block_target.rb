# frozen_string_literal: true

class SchemaBlockTarget < ApplicationRecord
  belongs_to :schema_target

  validates :block_descriptor_id, presence: true,
                                  uniqueness: { scope: :schema_target_id }
end
