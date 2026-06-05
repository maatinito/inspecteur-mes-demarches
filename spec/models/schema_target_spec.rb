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
require 'rails_helper'

RSpec.describe SchemaTarget, type: :model do
  describe 'validations' do
    let(:demarche) { create(:demarche) }
    let(:valid_attrs) { { demarche: demarche, target_type: 'baserow' } }

    it 'est valide avec demarche + target_type baserow' do
      expect(SchemaTarget.new(valid_attrs)).to be_valid
    end

    it 'est valide avec target_type grist' do
      expect(SchemaTarget.new(valid_attrs.merge(target_type: 'grist'))).to be_valid
    end

    it 'rejette un target_type inconnu' do
      record = SchemaTarget.new(valid_attrs.merge(target_type: 'notion'))
      expect(record).not_to be_valid
      expect(record.errors[:target_type]).to be_present
    end

    it 'exige demarche' do
      expect(SchemaTarget.new(target_type: 'baserow')).not_to be_valid
    end

    it 'exige target_type' do
      expect(SchemaTarget.new(demarche: demarche)).not_to be_valid
    end

    it 'unicité de (demarche_id, target_type)' do
      SchemaTarget.create!(valid_attrs)
      duplicate = SchemaTarget.new(valid_attrs)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:demarche_id]).to be_present
    end

    it 'autorise même démarche avec un target_type différent' do
      SchemaTarget.create!(valid_attrs)
      other = SchemaTarget.new(valid_attrs.merge(target_type: 'grist'))
      expect(other).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs_to demarche' do
      assoc = described_class.reflect_on_association(:demarche)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it 'has_many schema_block_targets dependent destroy' do
      assoc = described_class.reflect_on_association(:schema_block_targets)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end
  end

  describe 'exclusion de champs' do
    let(:target) { create(:schema_target) }

    describe '#field_excluded?' do
      it 'retourne false quand le field_id n’est pas exclu' do
        expect(target.field_excluded?('champ_xyz')).to be(false)
      end

      it 'retourne true quand le field_id est exclu' do
        target.update!(excluded_field_ids: ['champ_xyz'])
        expect(target.field_excluded?('champ_xyz')).to be(true)
      end

      it 'compare en string (accepte symbol ou integer)' do
        target.update!(excluded_field_ids: ['42'])
        expect(target.field_excluded?(42)).to be(true)
        expect(target.field_excluded?(:'42')).to be(true)
      end
    end

    describe '#exclude_field!' do
      it 'ajoute un field_id à excluded_field_ids' do
        target.exclude_field!('champ_xyz')
        expect(target.reload.excluded_field_ids).to eq(['champ_xyz'])
      end

      it 'idempotent (ajouter deux fois ne duplique pas)' do
        target.exclude_field!('champ_xyz')
        target.exclude_field!('champ_xyz')
        expect(target.reload.excluded_field_ids).to eq(['champ_xyz'])
      end

      it 'préserve les exclusions existantes' do
        target.update!(excluded_field_ids: ['existant'])
        target.exclude_field!('nouveau')
        expect(target.reload.excluded_field_ids).to contain_exactly('existant', 'nouveau')
      end
    end

    describe '#include_field!' do
      it 'retire un field_id de excluded_field_ids' do
        target.update!(excluded_field_ids: %w[a b c])
        target.include_field!('b')
        expect(target.reload.excluded_field_ids).to eq(%w[a c])
      end

      it 'idempotent (retirer un absent ne fait rien)' do
        target.update!(excluded_field_ids: ['a'])
        target.include_field!('absent')
        expect(target.reload.excluded_field_ids).to eq(['a'])
      end
    end
  end

  describe 'exclusion de blocs' do
    let(:target) { create(:schema_target) }

    describe '#block_excluded?' do
      it 'retourne false quand le block_id n’est pas exclu' do
        expect(target.block_excluded?('bloc_xyz')).to be(false)
      end

      it 'retourne true quand le block_id est exclu' do
        target.update!(excluded_block_descriptor_ids: ['bloc_xyz'])
        expect(target.block_excluded?('bloc_xyz')).to be(true)
      end
    end

    describe '#exclude_block!' do
      it 'ajoute un block_id à excluded_block_descriptor_ids' do
        target.exclude_block!('bloc_xyz')
        expect(target.reload.excluded_block_descriptor_ids).to eq(['bloc_xyz'])
      end

      it 'idempotent (ajouter deux fois ne duplique pas)' do
        target.exclude_block!('bloc_xyz')
        target.exclude_block!('bloc_xyz')
        expect(target.reload.excluded_block_descriptor_ids).to eq(['bloc_xyz'])
      end
    end

    describe '#include_block!' do
      it 'retire un block_id de excluded_block_descriptor_ids' do
        target.update!(excluded_block_descriptor_ids: %w[a b c])
        target.include_block!('b')
        expect(target.reload.excluded_block_descriptor_ids).to eq(%w[a c])
      end

      it 'idempotent (retirer un absent ne fait rien)' do
        target.update!(excluded_block_descriptor_ids: ['a'])
        target.include_block!('absent')
        expect(target.reload.excluded_block_descriptor_ids).to eq(['a'])
      end
    end
  end
end
