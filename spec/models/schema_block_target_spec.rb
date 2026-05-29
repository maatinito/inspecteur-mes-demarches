# frozen_string_literal: true

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
end
