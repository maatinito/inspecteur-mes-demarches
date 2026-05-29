# frozen_string_literal: true

class SchemaTarget < ApplicationRecord
  belongs_to :demarche
  has_many :schema_block_targets, dependent: :destroy

  enum :target_type, { baserow: 'baserow', grist: 'grist' }, validate: true

  validates :demarche_id, uniqueness: { scope: :target_type }
end
