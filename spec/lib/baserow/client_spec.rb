# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Baserow::Client do
  let(:base_url) { 'https://baserow.mes-demarches.gov.pf' }
  let(:api_token) { 'test_api_token' }
  let(:client) { described_class.new(base_url, api_token) }
  let(:table_id) { '42' }
  let(:row_id) { '123' }

  describe '#initialize' do
    it 'sets the base URL and API token' do
      expect(client.base_url).to eq(base_url)
    end
  end

  describe 'API methods' do
    let(:success_response) do
      instance_double(Typhoeus::Response,
                      code: 200,
                      body: '{"id": 1, "name": "Test"}')
    end

    let(:error_response) do
      instance_double(Typhoeus::Response,
                      code: 404,
                      body: '{"error": "Not Found"}')
    end

    before do
      allow(Typhoeus::Request).to receive(:new).and_return(instance_double(Typhoeus::Request, run: success_response))
    end

    describe '#get_table' do
      it 'makes a GET request to the table endpoint' do
        expected_url = "#{base_url}/api/database/tables/#{table_id}/"
        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :get)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.get_table(table_id)
      end
    end

    describe '#list_rows' do
      it 'makes a GET request to the rows endpoint' do
        expected_url = "#{base_url}/api/database/rows/table/#{table_id}/"
        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :get)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.list_rows(table_id)
      end

      it 'includes query parameters when provided' do
        params = { page: 1, size: 10 }
        expected_url = "#{base_url}/api/database/rows/table/#{table_id}/?page=1&size=10"
        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :get)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.list_rows(table_id, params)
      end
    end

    describe '#create_row' do
      it 'makes a POST request to the rows endpoint with the provided data' do
        data = { name: 'Test Row' }
        expected_url = "#{base_url}/api/database/rows/table/#{table_id}/?user_field_names=true"
        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :post, body: data.to_json)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.create_row(table_id, data)
      end
    end

    describe '#update_row' do
      it 'makes a PATCH request to the row endpoint with the provided data' do
        data = { name: 'Updated Row' }
        expected_url = "#{base_url}/api/database/rows/table/#{table_id}/#{row_id}/?user_field_names=true"
        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :patch, body: data.to_json)
        ).and_return(instance_double(Typhoeus::Request, run: success_response))

        client.update_row(table_id, row_id, data)
      end
    end

    describe '#delete_row' do
      let(:delete_response) do
        instance_double(Typhoeus::Response, code: 204, body: '')
      end

      it 'makes a DELETE request to the row endpoint' do
        expected_url = "#{base_url}/api/database/rows/table/#{table_id}/#{row_id}/"
        expect(Typhoeus::Request).to receive(:new).with(
          expected_url,
          hash_including(method: :delete)
        ).and_return(instance_double(Typhoeus::Request, run: delete_response))

        result = client.delete_row?(table_id, row_id)
        expect(result).to be true
      end
    end

    describe '#handle_response' do
      context 'when the response is successful' do
        it 'parses the JSON response' do
          result = client.send(:handle_response, success_response)
          expect(result).to eq({ 'id' => 1, 'name' => 'Test' })
        end
      end

      context 'when the response is a 204 No Content' do
        let(:no_content_response) do
          instance_double(Typhoeus::Response, code: 204, body: '')
        end

        it 'returns nil' do
          result = client.send(:handle_response, no_content_response)
          expect(result).to be_nil
        end
      end

      context 'when the response is an error' do
        it 'raises an ApiError with the error data' do
          error = nil
          expect { client.send(:handle_response, error_response) }
            .to(raise_error { |raised_error| error = raised_error })

          expect(error).to be_a(Baserow::ApiError)
          expect(error.status_code).to eq(404)
          expect(error.error_data).to eq({ 'error' => 'Not Found' })
        end
      end
    end
  end
end
