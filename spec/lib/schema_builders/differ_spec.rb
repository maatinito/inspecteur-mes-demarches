# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Style/OneClassPerFile, Naming/MethodParameterName

# Stub minimal d'un champ_descriptor GraphQL pour le Differ.
class TestDifferDescriptor
  attr_reader :id, :label, :__typename, :options

  def initialize(id:, label:, typename:, options: nil)
    @id = id
    @label = label
    @__typename = typename
    @options = options
  end
end

# Stub minimal d'un bloc répétable (avec champ_descriptors internes).
class TestDifferBlockDescriptor
  attr_reader :id, :label, :__typename, :champ_descriptors

  def initialize(id:, label:, champ_descriptors:)
    @id = id
    @label = label
    @__typename = 'RepetitionChampDescriptor'
    @champ_descriptors = champ_descriptors
  end
end

# Stub minimal d'un demarche_descriptor GraphQL.
TestDifferDemarcheDescriptor = Struct.new(:champ_descriptors)

# rubocop:enable Style/OneClassPerFile, Naming/MethodParameterName

RSpec.describe SchemaBuilders::Differ do
  let(:demarche) { create(:demarche) }
  let(:schema_target) do
    create(:schema_target,
           demarche: demarche,
           target_type: 'baserow',
           main_table_external_id: '101',
           excluded_field_ids: ['exclu_id'])
  end
  let(:adapter) { instance_double(SchemaBuilders::BaserowTarget) }

  let(:champ_a) { TestDifferDescriptor.new(id: 'a', label: 'Adresse', typename: 'TextChampDescriptor') }
  let(:champ_b) do
    TestDifferDescriptor.new(id: 'b', label: 'Statut', typename: 'DropDownListChampDescriptor', options: %w[Oui Non])
  end
  let(:champ_c) { TestDifferDescriptor.new(id: 'c', label: 'Email', typename: 'EmailChampDescriptor') }
  let(:champ_excluded) { TestDifferDescriptor.new(id: 'exclu_id', label: 'Notes', typename: 'TextChampDescriptor') }

  let(:demarche_descriptor) do
    TestDifferDemarcheDescriptor.new([champ_a, champ_b, champ_c, champ_excluded])
  end

  let(:differ) do
    described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: demarche_descriptor)
  end

  describe '#main_table_diff' do
    context 'avec une table cible existante' do
      before do
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                              { 'name' => 'Adresse', 'type' => 'text' },
                                                                              { 'name' => 'Statut', 'type' => 'text' }
                                                                            ])
      end

      it 'classe le champ conforme dans ok' do
        diff = differ.main_table_diff
        expect(diff[:ok].map { |f| f[:id] }).to include('a')
      end

      it 'classe le champ manquant dans to_add' do
        diff = differ.main_table_diff
        expect(diff[:to_add].map { |f| f[:id] }).to include('c')
      end

      it 'classe le champ avec type divergent dans to_modify (numeric vs text)' do
        numeric_champ = TestDifferDescriptor.new(id: 'n', label: 'Montant',
                                                 typename: 'IntegerNumberChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([numeric_champ])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                              { 'name' => 'Montant', 'type' => 'text' }
                                                                            ])
        diff = d.main_table_diff
        expect(diff[:to_modify].map { |f| f[:id] }).to include('n')
        expect(diff[:to_modify].first[:divergence]).to be_present
      end

      it 'classe les champs exclus dans excluded même s\'ils manquent côté cible' do
        diff = differ.main_table_diff
        expect(diff[:excluded].map { |f| f[:id] }).to eq(['exclu_id'])
        expect(diff[:to_add].map { |f| f[:id] }).not_to include('exclu_id')
      end

      it 'ignore les RepetitionChampDescriptor' do
        repetition = TestDifferBlockDescriptor.new(id: 'rep', label: 'Membres', champ_descriptors: [])
        descriptor = TestDifferDemarcheDescriptor.new([champ_a, repetition])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        diff = d.main_table_diff
        all_ids = diff.values.flatten.map { |f| f[:id] }
        expect(all_ids).not_to include('rep')
      end
    end

    context 'avec une table inexistante (premier Build)' do
      before do
        schema_target.update!(main_table_external_id: nil)
      end

      it 'classe tout en to_add (sauf exclus)' do
        diff = differ.main_table_diff
        expect(diff[:to_add].map { |f| f[:id] }).to contain_exactly('a', 'b', 'c')
        expect(diff[:excluded].map { |f| f[:id] }).to eq(['exclu_id'])
      end

      it 'ne fait pas d\'appel à adapter.get_table_fields' do
        expect(adapter).not_to receive(:get_table_fields)
        differ.main_table_diff
      end
    end
  end
end
