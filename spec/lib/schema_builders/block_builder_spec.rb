# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Style/OneClassPerFile, Naming/MethodParameterName

# Stub minimal pour les descripteurs GraphQL utilisés par BlockBuilder.
class TestBlockDescriptor
  attr_reader :label, :__typename, :id, :options

  def initialize(label:, typename:, id: nil, options: nil)
    @label = label
    @__typename = typename
    @id = id
    @options = options
  end

  def to_h
    h = { 'label' => label, '__typename' => __typename }
    h['options'] = options if options
    h
  end
end

class TestBlockRepetition
  attr_reader :label, :__typename, :id, :champ_descriptors

  def initialize(label:, id:, champ_descriptors:)
    @label = label
    @__typename = 'RepetitionChampDescriptor'
    @id = id
    @champ_descriptors = champ_descriptors
  end
end

TestBlockDemarcheDescriptor = Struct.new(:champ_descriptors, :annotation_descriptors)

# rubocop:enable Style/OneClassPerFile, Naming/MethodParameterName

RSpec.describe SchemaBuilders::BlockBuilder do
  let(:inner_fields) do
    [
      TestBlockDescriptor.new(label: 'Nom item', typename: 'TextChampDescriptor'),
      TestBlockDescriptor.new(label: 'Quantité', typename: 'IntegerNumberChampDescriptor'),
      TestBlockDescriptor.new(label: 'Section', typename: 'HeaderSectionChampDescriptor')
    ]
  end

  let(:block1) do
    TestBlockRepetition.new(label: 'Articles', id: 'B1', champ_descriptors: inner_fields)
  end

  let(:block2) do
    TestBlockRepetition.new(label: 'Pièces', id: 'B2', champ_descriptors: [
                              TestBlockDescriptor.new(label: 'Type', typename: 'TextChampDescriptor')
                            ])
  end

  let(:demarche_descriptor) do
    TestBlockDemarcheDescriptor.new(
      [
        TestBlockDescriptor.new(label: 'Texte simple', typename: 'TextChampDescriptor'),
        block1
      ],
      [block2]
    )
  end

  describe 'avec une cible Baserow' do
    let(:target) { instance_double(SchemaBuilders::BaserowTarget) }
    let(:type_mapper) { SchemaBuilders::TypeMapper.for(:baserow) }
    let(:builder) { described_class.new(target: target, type_mapper: type_mapper) }

    describe '#preview' do
      it 'retourne une entrée par bloc répétable (champs + annotations)' do
        preview = builder.preview(demarche_descriptor, application_id: 17, main_table_id: 100)
        names = preview.map { |b| b[:table_name] }
        expect(names).to contain_exactly('Articles', 'Pièces')
      end

      it 'inclut les block_descriptor_id' do
        preview = builder.preview(demarche_descriptor, application_id: 17, main_table_id: 100)
        ids = preview.map { |b| b[:block_descriptor_id] }
        expect(ids).to contain_exactly('B1', 'B2')
      end

      it 'inclut les champs métier filtrés (pas de sections)' do
        preview = builder.preview(demarche_descriptor, application_id: 17, main_table_id: 100)
        articles = preview.find { |b| b[:table_name] == 'Articles' }
        names = articles[:fields].map { |f| f[:name] }
        expect(names).to include('Nom item', 'Quantité')
        expect(names).not_to include('Section')
      end

      it 'ajoute les champs structurels Ligne et Dossier (link_row vers la table principale)' do
        preview = builder.preview(demarche_descriptor, application_id: 17, main_table_id: 100)
        articles = preview.find { |b| b[:table_name] == 'Articles' }

        ligne = articles[:fields].find { |f| f[:name] == 'Ligne' }
        expect(ligne).to include(type: 'number', number_decimal_places: 0)

        dossier = articles[:fields].find { |f| f[:name] == 'Dossier' }
        expect(dossier).to include(
          type: 'link_row',
          link_row_table_id: 100,
          link_row_multiple_relationships: false
        )
      end
    end

    describe '#build!' do
      it 'crée chaque bloc absent et update chaque bloc présent' do
        allow(target).to receive(:table_exists?).with(17, 'Articles').and_return(false)
        allow(target).to receive(:table_exists?).with(17, 'Pièces').and_return(true)
        allow(target).to receive(:list_tables).with(17).and_return([{ 'id' => 50, 'name' => 'Pièces' }])
        allow(target).to receive(:create_table).with(17, 'Articles', kind_of(Array)).and_return({ 'id' => 60 })
        allow(target).to receive(:update_fields)

        results = builder.build!(demarche_descriptor, application_id: 17, main_table_id: 100)

        expect(target).to have_received(:create_table).with(17, 'Articles', kind_of(Array))
        expect(target).to have_received(:update_fields).with(50, kind_of(Array))

        articles = results.find { |r| r[:table_name] == 'Articles' }
        pieces = results.find { |r| r[:table_name] == 'Pièces' }
        expect(articles).to include(table_id: 60, action: :created)
        expect(pieces).to include(table_id: 50, action: :updated)
      end
    end
  end

  describe 'avec une cible Grist' do
    let(:target) { instance_double(SchemaBuilders::GristTarget) }
    let(:type_mapper) { SchemaBuilders::TypeMapper.for(:grist) }
    let(:builder) { described_class.new(target: target, type_mapper: type_mapper) }

    it 'préfixe les champs structurels Ligne/Dossier/Bloc au format Grist' do
      preview = builder.preview(demarche_descriptor, application_id: 'doc1', main_table_id: 'MainTable')
      articles = preview.find { |b| b[:table_name] == 'Articles' }

      ids = articles[:fields].map { |f| f[:id] }
      expect(ids).to include('Ligne', 'Dossier', 'Bloc')

      dossier = articles[:fields].find { |f| f[:id] == 'Dossier' }
      expect(dossier[:fields]).to include(type: 'Ref:MainTable')

      bloc = articles[:fields].find { |f| f[:id] == 'Bloc' }
      expect(bloc[:fields]).to include(isFormula: true)
    end

    it 'inclut les champs métier au format Grist' do
      preview = builder.preview(demarche_descriptor, application_id: 'doc1', main_table_id: 'MainTable')
      articles = preview.find { |b| b[:table_name] == 'Articles' }

      labels = articles[:fields].map { |f| f[:fields][:label] }
      expect(labels).to include('Nom item', 'Quantité')
    end
  end
end
