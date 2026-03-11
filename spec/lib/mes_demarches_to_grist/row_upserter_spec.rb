# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToGrist::RowUpserter do
  let(:client) { instance_double(Grist::Client) }
  let(:doc_id) { 'aBC123xYz' }
  let(:table_id) { 'Dossiers' }
  let(:table) { Grist::Table.new(client, doc_id, table_id) }
  let(:options) { {} }
  let(:field_metadata) do
    {
      'Dossier' => { type: 'Integer', id: 'Dossier', isFormula: false },
      'Statut' => { type: 'Choice', id: 'Statut', isFormula: false },
      'Nom' => { type: 'Text', id: 'Nom', isFormula: false },
      'Age' => { type: 'Integer', id: 'Age', isFormula: false }
    }
  end
  let(:upserter) { described_class.new(table, options, field_metadata) }

  describe '#upsert_row' do
    context 'when no existing record is provided' do
      it 'performs upsert and finds the record ID' do
        data = { 'Statut' => 'en_construction', 'Nom' => 'Dupont' }

        expect(client).to receive(:upsert_records).with(
          doc_id, table_id,
          [{ require: { 'Dossier' => 42 }, fields: hash_including('Dossier' => 42) }]
        )

        filter_json = { 'Dossier' => [42] }.to_json
        expect(client).to receive(:list_records).with(
          doc_id, table_id, { filter: filter_json }
        ).and_return({ 'records' => [{ 'id' => 1, 'fields' => { 'Dossier' => 42 } }] })

        result = upserter.upsert_row(42, data)
        expect(result).to eq(1)
      end
    end

    context 'when existing record is provided and no changes' do
      it 'skips upsert' do
        existing_record = {
          'id' => 1,
          'fields' => { 'Dossier' => 42, 'Statut' => 'en_construction', 'Nom' => 'Dupont' }
        }
        data = { 'Statut' => 'en_construction', 'Nom' => 'Dupont' }

        expect(client).not_to receive(:upsert_records)

        result = upserter.upsert_row(42, data, existing_record: existing_record)
        expect(result).to eq(1)
      end
    end

    context 'when existing record is provided and has changes' do
      it 'performs upsert with only changed fields' do
        existing_record = {
          'id' => 1,
          'fields' => { 'Dossier' => 42, 'Statut' => 'en_construction', 'Nom' => 'Dupont' }
        }
        data = { 'Statut' => 'accepte', 'Nom' => 'Dupont' }

        expect(client).to receive(:upsert_records).with(
          doc_id, table_id,
          [{ require: { 'Dossier' => 42 }, fields: hash_including('Statut' => 'accepte') }]
        )

        filter_json = { 'Dossier' => [42] }.to_json
        expect(client).to receive(:list_records).with(
          doc_id, table_id, { filter: filter_json }
        ).and_return({ 'records' => [{ 'id' => 1 }] })

        upserter.upsert_row(42, data, existing_record: existing_record)
      end
    end
  end

  describe '#filter_changed_fields' do
    it 'detects text changes' do
      existing = { 'fields' => { 'Nom' => 'Dupont' } }
      new_data = { 'Nom' => 'Martin' }

      result = upserter.send(:filter_changed_fields, new_data, existing)
      expect(result).to eq({ 'Nom' => 'Martin' })
    end

    it 'ignores unchanged text fields' do
      existing = { 'fields' => { 'Nom' => 'Dupont' } }
      new_data = { 'Nom' => 'Dupont' }

      result = upserter.send(:filter_changed_fields, new_data, existing)
      expect(result).to be_empty
    end

    it 'detects number changes' do
      existing = { 'fields' => { 'Age' => 25 } }
      new_data = { 'Age' => 30 }

      result = upserter.send(:filter_changed_fields, new_data, existing)
      expect(result).to eq({ 'Age' => 30 })
    end

    it 'ignores unchanged numbers (string vs int)' do
      existing = { 'fields' => { 'Age' => 25 } }
      new_data = { 'Age' => 25 }

      result = upserter.send(:filter_changed_fields, new_data, existing)
      expect(result).to be_empty
    end
  end
end
