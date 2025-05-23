# frozen_string_literal: true

require 'typhoeus'
require 'json'

module Baserow
  class Client
    attr_reader :base_url

    def initialize(base_url, api_token)
      @base_url = base_url
      @api_token = api_token
      @headers = {
        'Authorization' => "Token #{api_token}",
        'Content-Type' => 'application/json'
      }
    end

    # Get a specific table by ID
    def get_table(table_id)
      response = make_request(:get, "/api/database/tables/#{table_id}/")
      handle_response(response)
    end

    # List fields for a table
    def list_fields(table_id)
      response = make_request(:get, "/api/database/fields/table/#{table_id}/")
      handle_response(response)
    end

    # List rows in a table
    def list_rows(table_id, params = {})
      query_params = build_query_params(params)
      url = "/api/database/rows/table/#{table_id}/#{query_params}"

      response = make_request(:get, url)
      handle_response(response)
    end

    # Get a specific row
    def get_row(table_id, row_id)
      response = make_request(:get, "/api/database/rows/table/#{table_id}/#{row_id}/")
      handle_response(response)
    end

    # Create a new row
    def create_row(table_id, data)
      response = make_request(:post, "/api/database/rows/table/#{table_id}/", body: data.to_json)
      handle_response(response)
    end

    # Update an existing row
    def update_row(table_id, row_id, data)
      response = make_request(:patch, "/api/database/rows/table/#{table_id}/#{row_id}/", body: data.to_json)
      handle_response(response)
    end

    # Delete a row
    def delete_row(table_id, row_id)
      response = make_request(:delete, "/api/database/rows/table/#{table_id}/#{row_id}/")
      response.code == 204
    end

    # Search for rows matching criteria
    def search_rows(table_id, search_params)
      filter_params = build_filter_params(search_params)
      list_rows(table_id, filter_params)
    end

    private

    def make_request(method, path, options = {})
      url = "#{@base_url}#{path}"

      request_options = {
        method:,
        headers: @headers,
        timeout: 30
      }

      request_options.merge!(options)
      puts "url=#{url}, headers=#{@headers}"
      Typhoeus::Request.new(url, request_options).run
    end

    def handle_response(response)
      pp response
      case response.code
      when 200, 201, 202
        JSON.parse(response.body)
      when 204
        nil # No content
      else
        error = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          { 'error' => response.body, 'status_code' => response.code }
        end

        raise ApiError.new(error, response.code)
      end
    end

    def build_query_params(params)
      return '' if params.empty?

      query_string = params.map do |key, value|
        "#{key}=#{CGI.escape(value.to_s)}"
      end.join('&')
      puts query_string
      "?#{query_string}"
    end

    def build_filter_params(search_params)
      filter_params = {}

      search_params.each_with_index do |(field, value), _index|
        filter_params["filter__field_#{field}__contains"] = value
      end

      filter_params
    end
  end

  class ApiError < StandardError
    attr_reader :error_data, :status_code

    def initialize(error_data, status_code)
      @error_data = error_data
      @status_code = status_code
      super("Baserow API Error: #{status_code} - #{error_data.inspect}")
    end
  end
end
