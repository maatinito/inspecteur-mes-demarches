# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Grist::Client do
  let(:base_url) { 'https://grist.mes-demarches.gov.pf' }
  let(:api_key) { 'test_api_key' }
  let(:client) { described_class.new(base_url, api_key) }
  let(:doc_id) { 'aBC123xYz' }
  let(:table_id) { 'Dossiers' }

  describe '#initialize' do
    it 'sets the base URL' do
      expect(client.base_url).to eq(base_url)
    end
  end

  describe 'API methods' do
    let(:success_response) do
      instance_double(Typhoeus::Response,
                      code: 200,
                      body: '{"records": [{"id": 1, "fields": {"Dossier": 42}}]}')
    end

    let(:error_response) do
      instance_double(Typhoeus::Response,
                      code: 404,
                      body: '{"error": "Not Found"}')
    end

    before do
      allow(Typhoeus::Request).to receive(:new).and_return(instance_double(Typhoeus::Request, run: success_response))
    end

    describe '#list_records' do
      it 'makes a GET request with Bearer auth' do
        expected_url = "#{base_url}/api/docs/#{doc_id}/tables/#{table_id}/records"
        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(
            method: :get,
            headers: hash_including('Authorization' => "Bearer #{api_key}")
          )
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.list_records(doc_id, table_id)
      end
    end

    describe '#add_records' do
      it 'makes a POST request with records wrapped in fields' do
        records = [{ 'Dossier' => 42, 'Statut' => 'en_construction' }]
        expected_body = { records: [{ fields: records.first }] }.to_json
        expected_url = "#{base_url}/api/docs/#{doc_id}/tables/#{table_id}/records"

        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :post, body: expected_body)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.add_records(doc_id, table_id, records)
      end
    end

    describe '#upsert_records' do
      it 'makes a PUT request with noparse=true' do
        records = [{ require: { 'Dossier' => 42 }, fields: { 'Statut' => 'accepte' } }]
        expected_url = "#{base_url}/api/docs/#{doc_id}/tables/#{table_id}/records?noparse=true"

        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :put)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.upsert_records(doc_id, table_id, records)
      end
    end

    describe '#delete_records' do
      it 'makes a POST request to data/delete' do
        ids = [1, 2, 3]
        expected_url = "#{base_url}/api/docs/#{doc_id}/tables/#{table_id}/data/delete"

        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :post, body: ids.to_json)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.delete_records(doc_id, table_id, ids)
      end
    end

    describe '#list_organizations' do
      it 'makes a GET request to /api/orgs' do
        expected_url = "#{base_url}/api/orgs"
        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :get)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.list_organizations
      end
    end

    describe '#list_columns' do
      it 'makes a GET request to columns endpoint' do
        expected_url = "#{base_url}/api/docs/#{doc_id}/tables/#{table_id}/columns"
        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :get)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.list_columns(doc_id, table_id)
      end
    end

    describe '#create_columns' do
      it 'makes a POST request to columns endpoint' do
        data = { columns: [{ id: 'Nom', fields: { type: 'Text' } }] }
        expected_url = "#{base_url}/api/docs/#{doc_id}/tables/#{table_id}/columns"

        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :post, body: data.to_json)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.create_columns(doc_id, table_id, data)
      end
    end

    describe 'response handling' do
      context 'when the response is successful' do
        it 'parses the JSON response' do
          result = client.send(:handle_response, success_response)
          expect(result).to eq({ 'records' => [{ 'id' => 1, 'fields' => { 'Dossier' => 42 } }] })
        end
      end

      context 'when the response is 204 No Content' do
        let(:no_content_response) { instance_double(Typhoeus::Response, code: 204, body: '') }

        it 'returns nil' do
          expect(client.send(:handle_response, no_content_response)).to be_nil
        end
      end

      context 'when the response is an error' do
        it 'raises a Grist::APIError' do
          expect { client.send(:handle_response, error_response) }
            .to raise_error(Grist::APIError) { |e|
              expect(e.status_code).to eq(404)
              expect(e.error_data).to eq({ 'error' => 'Not Found' })
            }
        end
      end
    end
  end
end
