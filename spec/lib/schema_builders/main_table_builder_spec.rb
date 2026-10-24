# frozen_string_literal: true

# rubocop:disable Naming/MethodParameterName

# Stub minimal mimant un descripteur de champ GraphQL : expose les méthodes
# `id`, `label`, `__typename`, et `to_h` (utilisée par TypeMapper).
class TestMainTableDescriptor
  attr_reader :id, :label, :__typename, :options

  def initialize(label:, typename:, options: nil, id: nil)
    @id = id
    @label = label
    @__typename = typename
    @options = options
  end

  def to_h
    h = { 'label' => label, '__typename' => __typename }
    h['id'] = id if id
    h['options'] = options if options
    h
  end
end

# Stub minimal mimant un demarche_descriptor GraphQL.
TestMainTableDemarcheDescriptor = Struct.new(:champ_descriptors, :annotation_descriptors)

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe SchemaBuilders::MainTableBuilder do
  def descriptor(label:, typename:, options: nil, id: nil)
    TestMainTableDescriptor.new(label: label, typename: typename, options: options, id: id)
  end

  # Démarche descriptor stub avec deux champs et une section ignorée.
  let(:demarche_descriptor) do
    TestMainTableDemarcheDescriptor.new(
      [
        descriptor(label: 'Nom', typename: 'TextChampDescriptor'),
        descriptor(label: 'Montant', typename: 'IntegerNumberChampDescriptor'),
        descriptor(label: 'Section', typename: 'HeaderSectionChampDescriptor'),
        descriptor(label: 'Bloc rep', typename: 'RepetitionChampDescriptor')
      ],
      []
    )
  end

  describe 'avec une cible Baserow' do
    let(:target) { instance_double(SchemaBuilders::BaserowTarget) }
    let(:type_mapper) { SchemaBuilders::TypeMapper.for(:baserow) }
    let(:builder) { described_class.new(target: target, type_mapper: type_mapper) }

    describe '#preview' do
      it 'retourne table_name + application_id + fields (specs natifs Baserow)' do
        preview = builder.preview(demarche_descriptor, application_id: 17, table_name: 'Dossiers')

        expect(preview[:table_name]).to eq('Dossiers')
        expect(preview[:application_id]).to eq(17)
        expect(preview[:fields]).to include(
          hash_including(name: 'Nom', type: 'text'),
          hash_including(name: 'Montant', type: 'number', number_decimal_places: 0)
        )
      end

      it 'omet les colonnes système exclues, jamais la colonne Dossier' do
        preview = builder.preview(demarche_descriptor, application_id: 17, table_name: 'Dossiers',
                                                       excluded_field_ids: %w[metadata:email_usager metadata:dossier])
        names = preview[:fields].map { |f| f[:name] }

        expect(names).to include('Dossier', 'Statut')
        expect(names).not_to include('Email usager')
      end

      it 'exclut les sections (HeaderSectionChampDescriptor)' do
        preview = builder.preview(demarche_descriptor, application_id: 17, table_name: 'Dossiers')
        names = preview[:fields].map { |f| f[:name] }
        expect(names).not_to include('Section')
      end

      it 'exclut les blocs répétables (RepetitionChampDescriptor, non supporté)' do
        preview = builder.preview(demarche_descriptor, application_id: 17, table_name: 'Dossiers')
        names = preview[:fields].map { |f| f[:name] }
        expect(names).not_to include('Bloc rep')
      end

      it 'inclut les annotations si include_annotations: true (par défaut)' do
        descriptor_with_annotations = TestMainTableDemarcheDescriptor.new(
          [descriptor(label: 'Nom', typename: 'TextChampDescriptor')],
          [descriptor(label: 'Note interne', typename: 'TextareaChampDescriptor')]
        )

        preview = builder.preview(descriptor_with_annotations, application_id: 17, table_name: 'X')
        names = preview[:fields].map { |f| f[:name] }
        expect(names).to include('Nom', 'Note interne')
      end

      it 'exclut les annotations si include_annotations: false' do
        descriptor_with_annotations = TestMainTableDemarcheDescriptor.new(
          [descriptor(label: 'Nom', typename: 'TextChampDescriptor')],
          [descriptor(label: 'Note interne', typename: 'TextareaChampDescriptor')]
        )

        preview = builder.preview(descriptor_with_annotations, application_id: 17, table_name: 'X', include_annotations: false)
        names = preview[:fields].map { |f| f[:name] }
        expect(names).to include('Nom')
        expect(names).not_to include('Note interne')
      end

      it 'respecte le field_filter quand fourni (call retourne false → skip)' do
        filter = instance_double('Filter')
        allow(filter).to receive(:call) { |d| d.label != 'Montant' }

        builder_with_filter = described_class.new(target: target, type_mapper: type_mapper, field_filter: filter)
        preview = builder_with_filter.preview(demarche_descriptor, application_id: 17, table_name: 'Dossiers')
        names = preview[:fields].map { |f| f[:name] }
        expect(names).to include('Nom')
        expect(names).not_to include('Montant')
      end
    end

    describe '#build!' do
      it 'appelle target.create_table quand la table n\'existe pas encore' do
        allow(target).to receive(:table_exists?).with(17, 'Dossiers').and_return(false)
        allow(target).to receive(:create_table).with(17, 'Dossiers', kind_of(Array)).and_return({ 'id' => 99, 'name' => 'Dossiers' })

        result = builder.build!(demarche_descriptor, application_id: 17, table_name: 'Dossiers')

        expect(target).to have_received(:create_table)
        expect(result[:table_id]).to eq(99)
        expect(result[:action]).to eq(:created)
        expect(result[:table_name]).to eq('Dossiers')
      end

      it 'appelle target.update_fields quand la table existe déjà' do
        allow(target).to receive(:table_exists?).with(17, 'Dossiers').and_return(true)
        allow(target).to receive(:list_tables).with(17).and_return([{ 'id' => 50, 'name' => 'Dossiers' }])
        allow(target).to receive(:table_ref) { |_app, tid| tid }
        allow(target).to receive(:update_fields)

        result = builder.build!(demarche_descriptor, application_id: 17, table_name: 'Dossiers')

        expect(target).to have_received(:update_fields).with(50, kind_of(Array))
        expect(result[:table_id]).to eq(50)
        expect(result[:action]).to eq(:updated)
      end

      it 'met à jour la table déjà sélectionnée (existing_table_id) sans la recréer' do
        allow(target).to receive(:list_tables).with(17).and_return([{ 'id' => 50, 'name' => 'Renommée' }])
        allow(target).to receive(:table_ref) { |_app, tid| tid }
        allow(target).to receive(:update_fields)
        allow(target).to receive(:create_table)

        result = builder.build!(demarche_descriptor, application_id: 17, table_name: 'Dossiers', existing_table_id: 50)

        expect(target).to have_received(:update_fields).with(50, kind_of(Array))
        expect(target).not_to have_received(:create_table)
        expect(result[:action]).to eq(:updated)
      end

      it 'recrée si existing_table_id n\'existe plus côté cible' do
        allow(target).to receive(:list_tables).with(17).and_return([{ 'id' => 99, 'name' => 'Autre' }])
        allow(target).to receive(:table_exists?).with(17, 'Dossiers').and_return(false)
        allow(target).to receive(:create_table).and_return({ 'id' => 123 })

        result = builder.build!(demarche_descriptor, application_id: 17, table_name: 'Dossiers', existing_table_id: 50)

        expect(target).to have_received(:create_table)
        expect(result[:action]).to eq(:created)
      end

      it 'transmet uniquement les champs supportés (post-filtrage) à create_table' do
        captured_fields = nil
        allow(target).to receive(:table_exists?).and_return(false)
        allow(target).to receive(:create_table) do |_app, _name, fields|
          captured_fields = fields
          { 'id' => 1 }
        end

        builder.build!(demarche_descriptor, application_id: 17, table_name: 'Dossiers')

        names = captured_fields.map { |f| f[:name] }
        # Champs de la démarche : seuls les types supportés passent.
        expect(names).to include('Nom', 'Montant')
        expect(names).not_to include('Section', 'Bloc rep')
      end

      it 'ajoute toujours la colonne primaire Dossier (numéro de dossier)' do
        captured_fields = nil
        allow(target).to receive(:table_exists?).and_return(false)
        allow(target).to receive(:create_table) do |_app, _name, fields|
          captured_fields = fields
          { 'id' => 1 }
        end

        builder.build!(demarche_descriptor, application_id: 17, table_name: 'Dossiers')

        dossier = captured_fields.find { |f| f[:name] == 'Dossier' }
        expect(dossier).to include(name: 'Dossier', type: 'number', number_decimal_places: 0)
      end

      it 'ajoute les colonnes système de métadonnées' do
        captured_fields = nil
        allow(target).to receive(:table_exists?).and_return(false)
        allow(target).to receive(:create_table) do |_app, _name, fields|
          captured_fields = fields
          { 'id' => 1 }
        end

        builder.build!(demarche_descriptor, application_id: 17, table_name: 'Dossiers')

        names = captured_fields.map { |f| f[:name] }
        expect(names).to include('Statut', 'Date de dépôt', 'Email usager', 'Groupe instructeur', 'Labels')
      end

      it 'déduplique une colonne métadonnée et un champ démarche de même libellé' do
        # « Raison sociale » existe comme champ demandeur (métadonnée morale) ET
        # comme annotation de la démarche : on ne doit créer la colonne qu'une fois.
        descriptor_with_collision = TestMainTableDemarcheDescriptor.new(
          [descriptor(id: 'rs', label: 'Raison sociale', typename: 'TextChampDescriptor')],
          []
        )

        captured_fields = nil
        allow(target).to receive(:table_exists?).and_return(false)
        allow(target).to receive(:create_table) do |_app, _name, fields|
          captured_fields = fields
          { 'id' => 1 }
        end

        builder.build!(descriptor_with_collision, application_id: 17, table_name: 'Dossiers', demandeur_modes: [:morale])

        names = captured_fields.map { |f| f[:name] }
        expect(names.count { |n| n == 'Raison sociale' }).to eq(1)
      end

      it 'ajoute les colonnes demandeur selon les modes détectés (:morale)' do
        captured_fields = nil
        allow(target).to receive(:table_exists?).and_return(false)
        allow(target).to receive(:create_table) do |_app, _name, fields|
          captured_fields = fields
          { 'id' => 1 }
        end

        builder.build!(demarche_descriptor, application_id: 17, table_name: 'Dossiers', demandeur_modes: [:morale])

        names = captured_fields.map { |f| f[:name] }
        expect(names).to include('Numéro TAHITI', 'Raison sociale')
        expect(names).not_to include('Civilité', 'Prénom')
      end

      it 'filtre les champs présents dans excluded_field_ids' do
        descriptor_with_ids = TestMainTableDemarcheDescriptor.new(
          [
            descriptor(id: 'champ_nom', label: 'Nom', typename: 'TextChampDescriptor'),
            descriptor(id: 'champ_montant', label: 'Montant', typename: 'IntegerNumberChampDescriptor')
          ],
          []
        )

        captured_fields = nil
        allow(target).to receive(:table_exists?).and_return(false)
        allow(target).to receive(:create_table) do |_app, _name, fields|
          captured_fields = fields
          { 'id' => 1 }
        end

        builder.build!(descriptor_with_ids, application_id: 17, table_name: 'Dossiers',
                                            excluded_field_ids: ['champ_montant'])

        names = captured_fields.map { |f| f[:name] }
        expect(names).to include('Nom')
        expect(names).not_to include('Montant')
      end

      it 'accepte des excluded_field_ids en symbol ou en string' do
        descriptor_with_ids = TestMainTableDemarcheDescriptor.new(
          [descriptor(id: 'a', label: 'Nom', typename: 'TextChampDescriptor')],
          []
        )

        captured_fields = nil
        allow(target).to receive(:table_exists?).and_return(false)
        allow(target).to receive(:create_table) do |_app, _name, fields|
          captured_fields = fields
          { 'id' => 1 }
        end

        builder.build!(descriptor_with_ids, application_id: 17, table_name: 'X',
                                            excluded_field_ids: [:a])

        # Le champ 'a' (Nom) est exclu ; seules les colonnes de métadonnées restent
        # (aucun demandeur_mode ici, donc pas de colonne demandeur 'Nom').
        names = captured_fields.map { |f| f[:name] }
        expect(names).not_to include('Nom')
        expect(names).to include('Dossier', 'Statut')
      end
    end
  end

  describe 'avec une cible Grist' do
    let(:target) { instance_double(SchemaBuilders::GristTarget) }
    let(:type_mapper) { SchemaBuilders::TypeMapper.for(:grist) }
    let(:builder) { described_class.new(target: target, type_mapper: type_mapper) }

    it 'produit des specs au format Grist (id + fields)' do
      preview = builder.preview(demarche_descriptor, application_id: 'doc1', table_name: 'Dossiers')

      expect(preview[:fields]).to all(include(:id, :fields))
      nom = preview[:fields].find { |f| f[:fields][:label] == 'Nom' }
      expect(nom[:fields]).to include(label: 'Nom', type: 'Text', isFormula: false)
    end

    it 'ajoute la colonne primaire Dossier (type Int) en tête' do
      preview = builder.preview(demarche_descriptor, application_id: 'doc1', table_name: 'Dossiers')

      expect(preview[:fields].first).to include(id: 'Dossier')
      expect(preview[:fields].first[:fields]).to include(label: 'Dossier', type: 'Int')
    end
  end
end
# rubocop:enable Metrics/BlockLength
# rubocop:enable Naming/MethodParameterName
