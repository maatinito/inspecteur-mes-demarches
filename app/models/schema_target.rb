# frozen_string_literal: true

# == Schema Information
#
# Table name: schema_targets
#
#  id                            :bigint           not null, primary key
#  excluded_block_descriptor_ids :jsonb            not null
#  excluded_field_ids            :jsonb            not null
#  last_synced_at                :datetime
#  referentiel                   :string           default("archive"), not null
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
class SchemaTarget < ApplicationRecord
  belongs_to :demarche
  has_many :schema_block_targets, dependent: :destroy

  enum :target_type, { baserow: 'baserow', grist: 'grist' }, validate: true

  EMAIL_USAGER_ID = 'metadata:email_usager'
  REFERENTIELS = %w[archive dlnuf].freeze

  validates :demarche_id, uniqueness: { scope: :target_type }
  validates :referentiel, inclusion: { in: REFERENTIELS }
  validate :dlnuf_reserve_a_baserow
  validate :referentiel_fige_apres_synchronisation, on: :update

  def dlnuf?
    referentiel == 'dlnuf'
  end

  # Exclusions réellement appliquées : en DLNUF, « Email usager » est obligatoire
  # (il sert de clé de scope du référentiel).
  def exclusions_effectives
    return excluded_field_ids unless dlnuf?

    excluded_field_ids - [EMAIL_USAGER_ID]
  end

  def type_mapper
    SchemaBuilders::TypeMapper.for(target_type.to_sym, referentiel: referentiel.to_sym)
  end

  def field_excluded?(field_id)
    exclusions_effectives.include?(field_id.to_s)
  end

  def exclude_field!(field_id)
    return if field_excluded?(field_id)

    update!(excluded_field_ids: excluded_field_ids + [field_id.to_s])
  end

  def include_field!(field_id)
    return unless field_excluded?(field_id)

    update!(excluded_field_ids: excluded_field_ids - [field_id.to_s])
  end

  def block_excluded?(block_id)
    excluded_block_descriptor_ids.include?(block_id.to_s)
  end

  def exclude_block!(block_id)
    return if block_excluded?(block_id)

    update!(excluded_block_descriptor_ids: excluded_block_descriptor_ids + [block_id.to_s])
  end

  def include_block!(block_id)
    return unless block_excluded?(block_id)

    update!(excluded_block_descriptor_ids: excluded_block_descriptor_ids - [block_id.to_s])
  end

  private

  def dlnuf_reserve_a_baserow
    errors.add(:referentiel, 'DLNUF est réservé à Baserow') if dlnuf? && !baserow?
  end

  # Le schéma créé dépend du type (PJ en texte ou en fichier) : on ne le change
  # plus une fois la table synchronisée.
  def referentiel_fige_apres_synchronisation
    return unless referentiel_changed? && last_synced_at_was.present?

    errors.add(:referentiel, 'ne peut plus changer après la première synchronisation du schéma')
  end
end
