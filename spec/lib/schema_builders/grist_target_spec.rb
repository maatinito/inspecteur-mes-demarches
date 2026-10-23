# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
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

    it 'normalise la réponse Grist vers { "id" => <tableId réel> }' do
      allow(client).to receive(:create_tables).and_return({ 'tables' => [{ 'id' => 'Ma_table' }] })

      expect(target.create_table('doc1', 'Ma table', [])).to eq({ 'id' => 'Ma_table' })
    end
  end

  describe '#table_ref' do
    it 'construit l\'id composite "doc_id:table_id"' do
      expect(target.table_ref('doc1', 'T1')).to eq('doc1:T1')
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

    # Grist tient les ids de colonne pour uniques sans égard à la casse et
    # renomme l'id d'une colonne liée à son libellé : apparier sur l'id exact
    # recréait à chaque build une copie suffixée (Dossier2, Dossier3…).
    it "retrouve une colonne existante dont l'id diffère par la casse et rétablit l'id attendu" do
      allow(client).to receive(:list_columns).and_return({
                                                           'columns' => [{ 'id' => 'dossier', 'fields' => { 'label' => 'Dossier' } }]
                                                         })
      expect(client).to receive(:update_column).with('doc1', 'T1', 'dossier', { label: 'Dossier', type: 'Int', colId: 'Dossier' })
      expect(client).not_to receive(:create_columns)

      target.update_fields('doc1:T1', [{ id: 'Dossier', fields: { label: 'Dossier', type: 'Int' } }])
    end

    it 'retrouve une colonne existante par son libellé quand Grist a dérivé un autre id' do
      allow(client).to receive(:list_columns).and_return({
                                                           'columns' => [{ 'id' => 'Agent_en_charge', 'fields' => { 'label' => 'Agent en charge' } }]
                                                         })
      expect(client).to receive(:update_column).with('doc1', 'T1', 'Agent_en_charge', { label: 'Agent en charge', type: 'Text' })
      expect(client).not_to receive(:create_columns)

      target.update_fields('doc1:T1', [{ id: 'agent_en_charge', fields: { label: 'Agent en charge', type: 'Text' } }])
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

    it 'apparie sur le libellé (fields.label) et pas seulement l\'id' do
      expect(client).to receive(:list_columns).with('doc1', 'T1').and_return({
                                                                               'columns' => [{ 'id' => 'nom', 'fields' => { 'label' => 'Nom' } }]
                                                                             })
      expect(target.field_exists?('doc1:T1', 'Nom')).to be true
    end
  end

  describe '#get_table_fields' do
    it 'normalise les colonnes avec le LIBELLÉ comme name (pas l\'id assaini)' do
      expect(client).to receive(:list_columns).with('doc1', 'T1').and_return({
                                                                               'columns' => [
                                                                                 { 'id' => 'nom', 'fields' => { 'label' => 'Nom', 'type' => 'Text' } },
                                                                                 { 'id' => 'montant', 'fields' => { 'label' => 'Montant', 'type' => 'Int' } }
                                                                               ]
                                                                             })

      expect(target.get_table_fields('doc1:T1')).to eq([
                                                         { 'name' => 'Nom', 'type' => 'Text' },
                                                         { 'name' => 'Montant', 'type' => 'Int' }
                                                       ])
    end

    it 'retombe sur l\'id de colonne si le libellé est absent' do
      expect(client).to receive(:list_columns).with('doc1', 'T1').and_return({
                                                                               'columns' => [{ 'id' => 'A', 'fields' => { 'type' => 'Text' } }]
                                                                             })

      expect(target.get_table_fields('doc1:T1')).to eq([{ 'name' => 'A', 'type' => 'Text' }])
    end
  end
end
# rubocop:enable Metrics/BlockLength
