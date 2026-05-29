# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchemaBuilders::GristTarget do
  let(:client) { instance_double(Grist::Client) }
  let(:target) { described_class.new(client: client) }

  it 'implémente l\'interface SchemaBuilders::Target' do
    expect(described_class.include?(SchemaBuilders::Target)).to be true
  end

  describe '#list_workspaces' do
    it 'aplatit les workspaces de toutes les orgs' do
      expect(client).to receive(:list_organizations).and_return([{ 'id' => 1 }, { 'id' => 2 }])
      expect(client).to receive(:list_workspaces).with(1).and_return([{ 'id' => 10, 'name' => 'A' }])
      expect(client).to receive(:list_workspaces).with(2).and_return([{ 'id' => 20, 'name' => 'B' }])

      expect(target.list_workspaces).to eq([
                                             { 'id' => 10, 'name' => 'A' },
                                             { 'id' => 20, 'name' => 'B' }
                                           ])
    end
  end

  describe '#list_applications' do
    it 'retourne les docs du workspace' do
      expect(client).to receive(:get_workspace).with(10).and_return({
                                                                      'id' => 10,
                                                                      'docs' => [{ 'id' => 'doc1' }, { 'id' => 'doc2' }]
                                                                    })
      expect(target.list_applications(10)).to eq([{ 'id' => 'doc1' }, { 'id' => 'doc2' }])
    end

    it 'retourne un tableau vide si pas de docs' do
      expect(client).to receive(:get_workspace).with(10).and_return({ 'id' => 10 })
      expect(target.list_applications(10)).to eq([])
    end
  end

  describe '#list_tables' do
    it 'retourne le tableau de tables (clé "tables")' do
      expect(client).to receive(:list_tables).with('doc1').and_return({
                                                                        'tables' => [{ 'id' => 'T1' }, { 'id' => 'T2' }]
                                                                      })
      expect(target.list_tables('doc1')).to eq([{ 'id' => 'T1' }, { 'id' => 'T2' }])
    end
  end

  describe '#create_table' do
    it 'délègue à create_tables avec un payload tables+columns' do
      expect(client).to receive(:create_tables).with('doc1', {
                                                       tables: [
                                                         { id: 'Ma_table',
                                                           columns: [{ id: 'A', fields: { label: 'A', type: 'Text' } }] }
                                                       ]
                                                     }).and_return({ 'tables' => [{ 'id' => 'Ma_table' }] })

      target.create_table('doc1', 'Ma_table', [{ id: 'A', fields: { label: 'A', type: 'Text' } }])
    end
  end

  describe '#update_fields' do
    it 'crée les colonnes manquantes et met à jour les existantes' do
      expect(client).to receive(:list_columns).with('doc1', 'T1').and_return({
                                                                               'columns' => [{ 'id' => 'A' }]
                                                                             })
      expect(client).to receive(:update_column).with('doc1', 'T1', 'A', { label: 'A bis', type: 'Text' })
      expect(client).to receive(:create_columns).with('doc1', 'T1', {
                                                        columns: [{ id: 'B', fields: { label: 'B', type: 'Text' } }]
                                                      })

      target.update_fields('doc1:T1', [
                             { id: 'A', fields: { label: 'A bis', type: 'Text' } },
                             { id: 'B', fields: { label: 'B', type: 'Text' } }
                           ])
    end

    it 'lève ArgumentError si table_id n\'est pas au format composite' do
      expect { target.update_fields('justatable', []) }.to raise_error(ArgumentError)
    end
  end

  describe '#table_exists?' do
    it 'retourne true quand une table porte ce nom' do
      expect(client).to receive(:list_tables).with('doc1').and_return({
                                                                        'tables' => [{ 'id' => 'Dossier' }, { 'id' => 'Autre' }]
                                                                      })
      expect(target.table_exists?('doc1', 'Dossier')).to be true
    end

    it 'retourne false sinon' do
      expect(client).to receive(:list_tables).with('doc1').and_return({ 'tables' => [{ 'id' => 'Autre' }] })
      expect(target.table_exists?('doc1', 'Dossier')).to be false
    end

    it 'retourne false en cas d\'erreur API' do
      expect(client).to receive(:list_tables).with('doc1').and_raise(Grist::APIError.new({ 'error' => 'fail' }, 500))
      expect(target.table_exists?('doc1', 'Dossier')).to be false
    end
  end

  describe '#field_exists?' do
    it 'retourne true si la colonne existe' do
      expect(client).to receive(:list_columns).with('doc1', 'T1').and_return({
                                                                               'columns' => [{ 'id' => 'A' }, { 'id' => 'B' }]
                                                                             })
      expect(target.field_exists?('doc1:T1', 'A')).to be true
    end

    it 'retourne false si la colonne n\'existe pas' do
      expect(client).to receive(:list_columns).with('doc1', 'T1').and_return({ 'columns' => [{ 'id' => 'A' }] })
      expect(target.field_exists?('doc1:T1', 'Z')).to be false
    end

    it 'retourne false en cas d\'erreur API' do
      expect(client).to receive(:list_columns).with('doc1', 'T1').and_raise(Grist::APIError.new({ 'error' => 'fail' }, 500))
      expect(target.field_exists?('doc1:T1', 'A')).to be false
    end
  end
end
