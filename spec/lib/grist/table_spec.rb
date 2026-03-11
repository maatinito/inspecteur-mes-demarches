# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Grist::Table do
  let(:client) { instance_double(Grist::Client) }
  let(:doc_id) { 'aBC123xYz' }
  let(:table_id) { 'Dossiers' }

  let(:columns_response) do
    {
      'columns' => [
        { 'id' => 'Dossier', 'fields' => { 'label' => 'Dossier', 'type' => 'Integer', 'isFormula' => false, 'formula' => '' } },
        { 'id' => 'Statut', 'fields' => { 'label' => 'Statut', 'type' => 'Choice', 'isFormula' => false, 'formula' => '' } },
        { 'id' => 'Bloc', 'fields' => { 'label' => 'Bloc', 'type' => 'Text', 'isFormula' => true, 'formula' => 'str($Dossier)' } }
      ]
    }
  end

  before do
    allow(client).to receive(:list_columns).with(doc_id, table_id).and_return(columns_response)
  end

  let(:table) { described_class.new(client, doc_id, table_id) }

  describe '#columns' do
    it 'lazy-loads column metadata' do
      expect(table.columns).to eq({
                                    'Dossier' => { id: 'Dossier', label: 'Dossier', type: 'Integer', isFormula: false, formula: '' },
                                    'Statut' => { id: 'Statut', label: 'Statut', type: 'Choice', isFormula: false, formula: '' },
                                    'Bloc' => { id: 'Bloc', label: 'Bloc', type: 'Text', isFormula: true, formula: 'str($Dossier)' }
                                  })
    end

    it 'caches the result' do
      table.columns
      table.columns
      expect(client).to have_received(:list_columns).once
    end
  end

  describe '#find_by' do
    it 'searches with filter parameter' do
      expected_filter = { 'Dossier' => [42] }.to_json
      expect(client).to receive(:list_records).with(
        doc_id, table_id, { filter: expected_filter }
      ).and_return({ 'records' => [{ 'id' => 1, 'fields' => { 'Dossier' => 42 } }] })

      results = table.find_by('Dossier', 42)
      expect(results).to eq([{ 'id' => 1, 'fields' => { 'Dossier' => 42 } }])
    end
  end

  describe '#list_records' do
    it 'delegates to the client' do
      params = { limit: 10 }
      expect(client).to receive(:list_records).with(doc_id, table_id, params)
      table.list_records(params)
    end
  end

  describe '#add_records' do
    it 'delegates to the client' do
      records = [{ 'Dossier' => 42 }]
      expect(client).to receive(:add_records).with(doc_id, table_id, records)
      table.add_records(records)
    end
  end

  describe '#upsert_records' do
    it 'delegates to the client' do
      records = [{ require: { 'Dossier' => 42 }, fields: { 'Statut' => 'accepte' } }]
      expect(client).to receive(:upsert_records).with(doc_id, table_id, records)
      table.upsert_records(records)
    end
  end

  describe '#delete_records' do
    it 'delegates to the client' do
      ids = [1, 2]
      expect(client).to receive(:delete_records).with(doc_id, table_id, ids)
      table.delete_records(ids)
    end
  end
end
