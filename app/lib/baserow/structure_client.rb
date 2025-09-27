# frozen_string_literal: true

require 'typhoeus'
require 'json'

module Baserow
  class StructureClient
    attr_reader :base_url

    def initialize(jwt_token = nil)
      @base_url = ENV.fetch('BASEROW_URL', 'https://baserow.mes-demarches.gov.pf')
      @jwt_token = jwt_token || AuthService.jwt_token
      @headers = {
        'Authorization' => "JWT #{@jwt_token}",
        'Content-Type' => 'application/json'
      }
    end

    def list_workspaces
      response = make_request(:get, '/api/workspaces/')
      handle_response(response)
    end

    def list_applications(workspace_id)
      response = make_request(:get, "/api/applications/?workspace=#{workspace_id}")
      handle_response(response)
    end

    def get_table_fields(table_id)
      response = make_request(:get, "/api/database/fields/table/#{table_id}/")
      handle_response(response)
    end

    def create_field(table_id, field_data)
      response = make_request(:post, "/api/database/fields/table/#{table_id}/", body: field_data.to_json)
      handle_response(response)
    end

    def field_exists?(table_id, field_name)
      fields = get_table_fields(table_id)
      fields.any? { |field| field['name']&.downcase == field_name.downcase }
    rescue Baserow::APIError
      false
    end

    def get_field_by_name(table_id, field_name)
      fields = get_table_fields(table_id)
      fields.find { |field| field['name']&.downcase == field_name.downcase }
    rescue Baserow::APIError
      nil
    end

    def update_field(field_id, field_data)
      response = make_request(:patch, "/api/database/fields/#{field_id}/", body: field_data.to_json)
      handle_response(response)
    end

    def get_primary_field(table_id)
      fields = get_table_fields(table_id)
      fields.find { |field| field['primary'] == true }
    rescue Baserow::APIError
      nil
    end

    def validate_primary_field(table_id, expected_name = 'Dossier', expected_type = 'number')
      primary_field = get_primary_field(table_id)

      return { valid: false, error: 'Aucun champ primaire trouvé' } unless primary_field

      if primary_field['name'] != expected_name
        return {
          valid: false,
          error: "Le champ primaire doit s'appeler '#{expected_name}' mais s'appelle '#{primary_field['name']}'"
        }
      end

      if primary_field['type'] != expected_type
        return {
          valid: false,
          error: "Le champ primaire doit être de type '#{expected_type}' mais est de type '#{primary_field['type']}'"
        }
      end

      { valid: true, field: primary_field }
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
      Typhoeus::Request.new(url, request_options).run
    end

    def handle_response(response)
      case response.code
      when 200, 201, 202
        JSON.parse(response.body)
      when 204
        nil
      when 401
        raise Baserow::APIError.new({ 'error' => 'Token JWT expiré ou invalide' }, response.code)
      when 403
        raise Baserow::APIError.new({ 'error' => 'Permissions insuffisantes' }, response.code)
      else
        error = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          { 'error' => response.body, 'status_code' => response.code }
        end

        raise Baserow::APIError.new(error, response.code)
      end
    end
  end
end
