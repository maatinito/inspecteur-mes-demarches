# frozen_string_literal: true

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
end
