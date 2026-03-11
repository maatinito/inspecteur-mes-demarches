# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GristSync do
  describe 'parameter validation' do
    let(:base_params) do
      {
        grist: { 'doc_id' => 'aBC123xYz', 'table_id' => 'Dossiers' },
        options: { 'continuer_si_erreur' => true }
      }
    end

    context 'when doc_id is missing' do
      it 'adds an error' do
        params = base_params.merge(grist: { 'table_id' => 'Dossiers' })
        checker = described_class.new(params)
        expect(checker.errors).to include("Configuration 'grist.doc_id' manquante sur grist_sync")
      end
    end

    context 'when table_id is missing' do
      it 'adds an error' do
        params = base_params.merge(grist: { 'doc_id' => 'aBC123xYz' })
        checker = described_class.new(params)
        expect(checker.errors).to include("Configuration 'grist.table_id' manquante sur grist_sync")
      end
    end

    context 'when include_repetable_blocks is true but blocks config is invalid' do
      it 'adds an error when repetable_blocks is nil' do
        params = base_params.merge(options: { 'include_repetable_blocks' => true })
        checker = described_class.new(params)
        expect(checker.errors).to include("Configuration 'options.repetable_blocks' invalide ou vide sur grist_sync")
      end

      it 'adds an error when repetable_blocks is empty' do
        params = base_params.merge(options: { 'include_repetable_blocks' => true, 'repetable_blocks' => [] })
        checker = described_class.new(params)
        expect(checker.errors).to include("Configuration 'options.repetable_blocks' invalide ou vide sur grist_sync")
      end
    end

    context 'when all params are valid' do
      it 'has no grist-specific errors' do
        checker = described_class.new(base_params)
        grist_errors = checker.errors.select { |e| e.include?('grist_sync') }
        expect(grist_errors).to be_empty
      end
    end
  end

  describe '#required_fields' do
    it 'includes :grist' do
      checker = described_class.new(grist: { 'doc_id' => 'x', 'table_id' => 'y' })
      expect(checker.required_fields).to include(:grist)
    end
  end

  describe '#authorized_fields' do
    it 'includes :options' do
      checker = described_class.new(grist: { 'doc_id' => 'x', 'table_id' => 'y' })
      expect(checker.authorized_fields).to include(:options)
    end
  end
end
