# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchemaBuilders::BaserowTarget do
  let(:client) { instance_double(Baserow::StructureClient) }
  let(:target) { described_class.new(client: client) }

  it 'implémente l\'interface SchemaBuilders::Target' do
    expect(described_class.include?(SchemaBuilders::Target)).to be true
  end

  describe '#list_workspaces' do
    it 'délègue au client Baserow' do
      expect(client).to receive(:list_workspaces).and_return([{ 'id' => 1, 'name' => 'WS1' }])
      expect(target.list_workspaces).to eq([{ 'id' => 1, 'name' => 'WS1' }])
    end
  end

  describe '#list_applications' do
    it 'délègue avec le workspace_id' do
      expect(client).to receive(:list_applications).with(42).and_return([{ 'id' => 10 }])
      expect(target.list_applications(42)).to eq([{ 'id' => 10 }])
    end
  end

  describe '#list_tables' do
    it 'délègue avec l\'application_id (database_id côté Baserow)' do
      expect(client).to receive(:list_tables).with(10).and_return([{ 'id' => 100, 'name' => 'T1' }])
      expect(target.list_tables(10)).to eq([{ 'id' => 100, 'name' => 'T1' }])
    end
  end

  describe '#create_table' do
    it 'crée la table puis chaque champ' do
      expect(client).to receive(:create_table).with(10, { name: 'Ma table' }).and_return({ 'id' => 100, 'name' => 'Ma table' })
      expect(client).to receive(:create_field).with(100, { name: 'A', type: 'text' })
      expect(client).to receive(:create_field).with(100, { name: 'B', type: 'number' })

      result = target.create_table(10, 'Ma table', [
                                     { name: 'A', type: 'text' },
                                     { name: 'B', type: 'number' }
                                   ])
      expect(result).to eq({ 'id' => 100, 'name' => 'Ma table' })
    end
  end

  describe '#update_fields' do
    it 'met à jour les champs existants et crée les manquants' do
      expect(client).to receive(:get_field_by_name).with(100, 'A').and_return({ 'id' => 1, 'name' => 'A' })
      expect(client).to receive(:update_field).with(1, { name: 'A', type: 'text' })

      expect(client).to receive(:get_field_by_name).with(100, 'B').and_return(nil)
      expect(client).to receive(:create_field).with(100, { name: 'B', type: 'number' })

      target.update_fields(100, [
                             { name: 'A', type: 'text' },
                             { name: 'B', type: 'number' }
                           ])
    end
  end

  describe '#table_exists?' do
    it 'retourne true si une table de ce nom existe' do
      expect(client).to receive(:list_tables).with(10).and_return([
                                                                    { 'id' => 100, 'name' => 'Mon Dossier' },
                                                                    { 'id' => 101, 'name' => 'Autre' }
                                                                  ])
      expect(target.table_exists?(10, 'Mon Dossier')).to be true
    end

    it 'retourne true en ignorant la casse' do
      expect(client).to receive(:list_tables).with(10).and_return([{ 'id' => 100, 'name' => 'Dossier' }])
      expect(target.table_exists?(10, 'DOSSIER')).to be true
    end

    it 'retourne false si aucune table ne correspond' do
      expect(client).to receive(:list_tables).with(10).and_return([{ 'id' => 100, 'name' => 'Autre' }])
      expect(target.table_exists?(10, 'Mon Dossier')).to be false
    end

    it 'retourne false en cas d\'erreur API' do
      expect(client).to receive(:list_tables).with(10).and_raise(Baserow::APIError.new({ 'error' => 'fail' }, 500))
      expect(target.table_exists?(10, 'X')).to be false
    end
  end

  describe '#field_exists?' do
    it 'délègue au client' do
      expect(client).to receive(:field_exists?).with(100, 'Dossier').and_return(true)
      expect(target.field_exists?(100, 'Dossier')).to be true
    end

    it 'retourne false quand le client le dit' do
      expect(client).to receive(:field_exists?).with(100, 'Inconnu').and_return(false)
      expect(target.field_exists?(100, 'Inconnu')).to be false
    end
  end
end
