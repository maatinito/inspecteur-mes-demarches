# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchemaBuilders::FieldFilter do
  describe '.for(unknown target)' do
    it 'lève ArgumentError pour une cible inconnue' do
      expect { described_class.for(:notion, foo: :bar) }
        .to raise_error(ArgumentError, /unknown target/)
    end
  end

  describe '.for(:baserow)' do
    let(:client) { instance_double(Baserow::Client) }
    let(:filter) { described_class.for(:baserow, table_id: 42, token_config: 'tftn') }

    before do
      allow(Baserow::Config).to receive(:client).with('tftn').and_return(client)
    end

    it 'retourne un BaserowFieldFilter' do
      expect(filter).to be_a(SchemaBuilders::BaserowFieldFilter)
    end

    it 'identifie les champs read-only via READONLY_TYPES' do
      allow(client).to receive(:list_fields).with(42).and_return([
                                                                   { 'id' => 1, 'name' => 'Nom', 'type' => 'text' },
                                                                   { 'id' => 2, 'name' => 'Calcul', 'type' => 'formula' },
                                                                   { 'id' => 3, 'name' => 'Lookup', 'type' => 'lookup' },
                                                                   { 'id' => 4, 'name' => 'Rollup', 'type' => 'rollup' },
                                                                   { 'id' => 5, 'name' => 'Compte', 'type' => 'count' },
                                                                   { 'id' => 6, 'name' => 'Créé le', 'type' => 'created_on' },
                                                                   { 'id' => 7, 'name' => 'MAJ', 'type' => 'last_modified' }
                                                                 ])
      filter.load_metadata
      expect(filter.readonly_field?('type' => 'formula')).to be true
      expect(filter.readonly_field?('type' => 'lookup')).to be true
      expect(filter.readonly_field?('type' => 'rollup')).to be true
      expect(filter.readonly_field?('type' => 'count')).to be true
      expect(filter.readonly_field?('type' => 'created_on')).to be true
      expect(filter.readonly_field?('type' => 'last_modified')).to be true
      expect(filter.readonly_field?('type' => 'text')).to be false
    end

    describe '#filter_syncable_fields' do
      before do
        allow(client).to receive(:list_fields).with(42).and_return([
                                                                     { 'id' => 1, 'name' => 'Nom', 'type' => 'text' },
                                                                     { 'id' => 2, 'name' => 'Calcul', 'type' => 'formula' }
                                                                   ])
      end

      it 'garde les champs writeable' do
        result = filter.filter_syncable_fields('Nom' => 'Jean', 'Calcul' => 42)
        expect(result).to eq('Nom' => 'Jean')
      end

      it 'exclut les champs absents de la cible' do
        result = filter.filter_syncable_fields('Nom' => 'Jean', 'Inconnu' => 'X')
        expect(result).to eq('Nom' => 'Jean')
      end

      it 'mémoize les métadonnées (un seul appel HTTP)' do
        filter.filter_syncable_fields('Nom' => 'X')
        filter.filter_syncable_fields('Nom' => 'Y')
        expect(client).to have_received(:list_fields).once
      end
    end

    describe '#load_baserow_fields (alias de compatibilité)' do
      it 'est un alias de load_metadata' do
        allow(client).to receive(:list_fields).with(42).and_return([])
        expect(filter.load_baserow_fields).to eq(filter.load_metadata)
      end
    end
  end

  describe '.for(:grist)' do
    let(:grist_table) { instance_double(Grist::Table) }
    let(:filter) { described_class.for(:grist, doc_id: 'doc1', table_id: 'Contacts', config_name: 'tftn') }

    before do
      allow(Grist::Config).to receive(:table).with('doc1', 'Contacts', 'tftn').and_return(grist_table)
    end

    it 'retourne un GristFieldFilter' do
      expect(filter).to be_a(SchemaBuilders::GristFieldFilter)
    end

    describe '#filter_syncable_fields' do
      before do
        allow(grist_table).to receive(:columns).and_return(
          'Nom' => { id: 'Nom', type: 'Text', isFormula: false },
          'Calcul' => { id: 'Calcul', type: 'Numeric', isFormula: true }
        )
      end

      it 'garde les colonnes writeable (isFormula=false)' do
        result = filter.filter_syncable_fields('Nom' => 'Jean', 'Calcul' => 42)
        expect(result).to eq('Nom' => 'Jean')
      end

      it 'exclut les colonnes calculées (isFormula=true)' do
        result = filter.filter_syncable_fields('Calcul' => 42)
        expect(result).to eq({})
      end

      it 'exclut les colonnes absentes de la cible' do
        result = filter.filter_syncable_fields('Inconnu' => 'X')
        expect(result).to eq({})
      end

      it 'mémoize les métadonnées' do
        filter.filter_syncable_fields('Nom' => 'X')
        filter.filter_syncable_fields('Nom' => 'Y')
        expect(grist_table).to have_received(:columns).once
      end
    end

    describe '#load_columns (alias de compatibilité)' do
      it 'est un alias de load_metadata' do
        allow(grist_table).to receive(:columns).and_return({})
        expect(filter.load_columns).to eq(filter.load_metadata)
      end
    end
  end
end
