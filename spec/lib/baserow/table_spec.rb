# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Baserow::Table do
  let(:client) { instance_double(Baserow::Client) }
  let(:table_id) { '42' }
  let(:table_name) { 'Test Table' }
  let(:table) { described_class.new(client, table_id, table_name) }

  describe '#initialize' do
    context 'when a table_id is provided' do
      it 'loads the fields for the table' do
        expect(client).to receive(:list_fields).with(table_id).and_return([
                                                                            { 'id' => 1, 'name' => 'Name', 'type' => 'text', 'primary' => true },
                                                                            { 'id' => 2, 'name' => 'Description', 'type' => 'long_text', 'primary' => false }
                                                                          ])

        table = described_class.new(client, table_id, table_name)

        expect(table.fields).to eq({
                                     'Name' => { id: 1, type: 'text', primary: true },
                                     'Description' => { id: 2, type: 'long_text', primary: false }
                                   })
      end
    end
  end

  describe '#list_rows' do
    it 'delegates to the client' do
      params = { page: 1, size: 10 }
      expect(client).to receive(:list_rows).with(table_id, params)

      table.list_rows(params)
    end
  end

  describe '#get_row' do
    it 'delegates to the client' do
      row_id = '123'
      expect(client).to receive(:get_row).with(table_id, row_id)

      table.get_row(row_id)
    end
  end

  describe '#create_row' do
    it 'delegates to the client' do
      data = { 'Name' => 'Test' }
      expect(client).to receive(:create_row).with(table_id, data)

      table.create_row(data)
    end
  end

  describe '#update_row' do
    it 'delegates to the client' do
      row_id = '123'
      data = { 'Name' => 'Updated Test' }
      expect(client).to receive(:update_row).with(table_id, row_id, data)

      table.update_row(row_id, data)
    end
  end

  describe '#delete_row' do
    it 'delegates to the client' do
      row_id = '123'
      expect(client).to receive(:delete_row).with(table_id, row_id)

      table.delete_row(row_id)
    end
  end

  describe '#find_by' do
    before do
      allow(client).to receive(:list_fields).with(table_id).and_return([
                                                                         { 'id' => 1, 'name' => 'Name', 'type' => 'text', 'primary' => true }
                                                                       ])

      table.load_fields
    end

    it 'searches by field equality' do
      expect(client).to receive(:list_rows).with(
        table_id,
        { 'filter__field_1__equal' => 'Test' }
      ).and_return({ 'results' => [{ 'id' => 123, 'Name' => 'Test' }] })

      results = table.find_by('Name', 'Test')
      expect(results).to eq([{ 'id' => 123, 'Name' => 'Test' }])
    end

    context 'when the field does not exist' do
      it 'raises an ArgumentError' do
        expect(client).to receive(:list_fields).with(table_id).and_return([
                                                                            { 'id' => 1, 'name' => 'Name', 'type' => 'text', 'primary' => true }
                                                                          ])

        expect { table.find_by('NonExistentField', 'Test') }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#search' do
    before do
      allow(client).to receive(:list_fields).with(table_id).and_return([
                                                                         { 'id' => 1, 'name' => 'Name', 'type' => 'text', 'primary' => true }
                                                                       ])

      table.load_fields
    end

    it 'searches by partial text match' do
      expect(client).to receive(:list_rows).with(
        table_id,
        { 'filter__field_1__contains' => 'Test' }
      ).and_return({ 'results' => [{ 'id' => 123, 'Name' => 'Test Item' }] })

      results = table.search('Name', 'Test')
      expect(results).to eq([{ 'id' => 123, 'Name' => 'Test Item' }])
    end
  end

  describe '#all' do
    it 'retrieves all rows with pagination' do
      expect(client).to receive(:list_rows).with(
        table_id,
        { page: 1, size: 100 }
      ).and_return({ 'results' => [{ 'id' => 123, 'Name' => 'Test' }] })

      results = table.all
      expect(results).to eq([{ 'id' => 123, 'Name' => 'Test' }])
    end
  end
end
