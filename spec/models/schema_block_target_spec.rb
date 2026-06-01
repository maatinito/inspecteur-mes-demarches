# frozen_string_literal: true

# == Schema Information
#
# Table name: schema_block_targets
#
#  id                  :bigint           not null, primary key
#  excluded_field_ids  :jsonb            not null
#  last_synced_at      :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  backend_table_id    :string
#  block_descriptor_id :string           not null
#  schema_target_id    :bigint           not null
#
# Indexes
#
#  idx_schema_block_targets_unique                 (schema_target_id,block_descriptor_id) UNIQUE
#  index_schema_block_targets_on_schema_target_id  (schema_target_id)
#
# Foreign Keys
#
#  fk_rails_...  (schema_target_id => schema_targets.id)
#
require 'rails_helper'

RSpec.describe SchemaBlockTarget, type: :model do
  describe 'validations' do
    let(:schema_target) { create(:schema_target) }
    let(:valid_attrs) { { schema_target: schema_target, block_descriptor_id: 'main' } }

    it 'est valide avec schema_target + block_descriptor_id' do
      expect(SchemaBlockTarget.new(valid_attrs)).to be_valid
    end

    it 'exige schema_target' do
      expect(SchemaBlockTarget.new(block_descriptor_id: 'main')).not_to be_valid
    end

    it 'exige block_descriptor_id' do
      expect(SchemaBlockTarget.new(schema_target: schema_target)).not_to be_valid
    end

    it 'unicité de (schema_target_id, block_descriptor_id)' do
      SchemaBlockTarget.create!(valid_attrs)
      duplicate = SchemaBlockTarget.new(valid_attrs)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:block_descriptor_id]).to be_present
    end

    it 'autorise même schema_target avec un block_descriptor_id différent' do
      SchemaBlockTarget.create!(valid_attrs)
      other = SchemaBlockTarget.new(valid_attrs.merge(block_descriptor_id: 'autre'))
      expect(other).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs_to schema_target' do
      assoc = described_class.reflect_on_association(:schema_target)
      expect(assoc.macro).to eq(:belongs_to)
    end
  end

  describe 'exclusion de champs' do
    let(:block_target) { create(:schema_block_target) }

    describe '#field_excluded?' do
      it 'retourne false quand le field_id n’est pas exclu' do
        expect(block_target.field_excluded?('champ_xyz')).to be(false)
      end

      it 'retourne true quand le field_id est exclu' do
        block_target.update!(excluded_field_ids: ['champ_xyz'])
        expect(block_target.field_excluded?('champ_xyz')).to be(true)
      end

      it 'compare en string (accepte symbol ou integer)' do
        block_target.update!(excluded_field_ids: ['42'])
        expect(block_target.field_excluded?(42)).to be(true)
      end
    end

    describe '#exclude_field!' do
      it 'ajoute un field_id à excluded_field_ids' do
        block_target.exclude_field!('champ_xyz')
        expect(block_target.reload.excluded_field_ids).to eq(['champ_xyz'])
      end

      it 'idempotent (ajouter deux fois ne duplique pas)' do
        block_target.exclude_field!('champ_xyz')
        block_target.exclude_field!('champ_xyz')
        expect(block_target.reload.excluded_field_ids).to eq(['champ_xyz'])
      end

      it 'préserve les exclusions existantes' do
        block_target.update!(excluded_field_ids: ['existant'])
        block_target.exclude_field!('nouveau')
        expect(block_target.reload.excluded_field_ids).to contain_exactly('existant', 'nouveau')
      end
    end

    describe '#include_field!' do
      it 'retire un field_id de excluded_field_ids' do
        block_target.update!(excluded_field_ids: %w[a b c])
        block_target.include_field!('b')
        expect(block_target.reload.excluded_field_ids).to eq(%w[a c])
      end

      it 'idempotent (retirer un absent ne fait rien)' do
        block_target.update!(excluded_field_ids: ['a'])
        block_target.include_field!('absent')
        expect(block_target.reload.excluded_field_ids).to eq(['a'])
      end
    end
  end
end
