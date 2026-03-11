# frozen_string_literal: true

require 'typhoeus'
require 'json'

module Grist
  # Client REST pour l'API Grist (Data + Structure)
  # Contrairement à Baserow, Grist utilise une seule clé API (Bearer) pour tout.
  class Client
    attr_reader :base_url

    def initialize(base_url, api_key)
      @base_url = base_url
      @api_key = api_key
      @headers = {
        'Authorization' => "Bearer #{api_key}",
        'Content-Type' => 'application/json'
      }
    end

    # === Data API ===

    # Liste les records d'une table
    # GET /api/docs/{docId}/tables/{tableId}/records
    def list_records(doc_id, table_id, params = {})
      query_params = build_query_params(params)
      response = make_request(:get, "/api/docs/#{doc_id}/tables/#{table_id}/records#{query_params}")
      handle_response(response)
    end

    # Ajoute des records à une table
    # POST /api/docs/{docId}/tables/{tableId}/records
    def add_records(doc_id, table_id, records)
      body = { records: records.map { |r| { fields: r } } }
      response = make_request(:post, "/api/docs/#{doc_id}/tables/#{table_id}/records", body: body.to_json)
      handle_response(response)
    end

    # Met à jour des records existants
    # PATCH /api/docs/{docId}/tables/{tableId}/records
    def update_records(doc_id, table_id, records)
      body = { records: records }
      response = make_request(:patch, "/api/docs/#{doc_id}/tables/#{table_id}/records", body: body.to_json)
      handle_response(response)
    end

    # Upsert natif Grist : crée ou met à jour selon les clés require
    # PUT /api/docs/{docId}/tables/{tableId}/records?noparse=true
    # Chaque record contient { require: {col: val}, fields: {col: val} }
    # Les clés de require déterminent le critère de matching
    def upsert_records(doc_id, table_id, records)
      body = { records: records }
      response = make_request(
        :put,
        "/api/docs/#{doc_id}/tables/#{table_id}/records?noparse=true",
        body: body.to_json
      )
      handle_response(response)
    end

    # Supprime des records par IDs
    # POST /api/docs/{docId}/tables/{tableId}/data/delete
    def delete_records(doc_id, table_id, ids)
      response = make_request(:post, "/api/docs/#{doc_id}/tables/#{table_id}/data/delete", body: ids.to_json)
      handle_response(response)
    end

    # === Structure API ===

    # Liste les organisations
    # GET /api/orgs
    def list_organizations
      response = make_request(:get, '/api/orgs')
      handle_response(response)
    end

    # Liste les workspaces d'une organisation
    # GET /api/orgs/{orgId}/workspaces
    def list_workspaces(org_id)
      response = make_request(:get, "/api/orgs/#{org_id}/workspaces")
      handle_response(response)
    end

    # Récupère un workspace (inclut les documents)
    # GET /api/workspaces/{wsId}
    def get_workspace(ws_id)
      response = make_request(:get, "/api/workspaces/#{ws_id}")
      handle_response(response)
    end

    # Liste les tables d'un document
    # GET /api/docs/{docId}/tables
    def list_tables(doc_id)
      response = make_request(:get, "/api/docs/#{doc_id}/tables")
      handle_response(response)
    end

    # Crée des tables dans un document
    # POST /api/docs/{docId}/tables
    def create_tables(doc_id, data)
      response = make_request(:post, "/api/docs/#{doc_id}/tables", body: data.to_json)
      handle_response(response)
    end

    # Liste les colonnes d'une table
    # GET /api/docs/{docId}/tables/{tableId}/columns
    def list_columns(doc_id, table_id)
      response = make_request(:get, "/api/docs/#{doc_id}/tables/#{table_id}/columns")
      handle_response(response)
    end

    # Crée des colonnes dans une table
    # POST /api/docs/{docId}/tables/{tableId}/columns
    def create_columns(doc_id, table_id, data)
      response = make_request(:post, "/api/docs/#{doc_id}/tables/#{table_id}/columns", body: data.to_json)
      handle_response(response)
    end

    # Met à jour une colonne
    # PUT /api/docs/{docId}/tables/{tableId}/columns/{colId}
    def update_column(doc_id, table_id, col_id, fields)
      response = make_request(:put, "/api/docs/#{doc_id}/tables/#{table_id}/columns/#{col_id}", body: fields.to_json)
      handle_response(response)
    end

    # === Fichiers ===

    # Récupère les métadonnées d'un attachment (fileName, fileSize)
    # GET /api/docs/{docId}/attachments/{attachmentId}
    def get_attachment_metadata(doc_id, attachment_id)
      response = make_request(:get, "/api/docs/#{doc_id}/attachments/#{attachment_id}")
      handle_response(response)
    end

    # Upload un fichier en pièce jointe
    # POST /api/docs/{docId}/attachments
    def upload_attachment(doc_id, file_path, _filename)
      upload_headers = {
        'Authorization' => "Bearer #{@api_key}"
      }
      response = Typhoeus.post(
        "#{@base_url}/api/docs/#{doc_id}/attachments",
        headers: upload_headers,
        body: { upload: File.open(file_path, 'rb') },
        timeout: 60
      )
      handle_response(response)
    end

    private

    def make_request(method, path, options = {})
      url = "#{@base_url}#{path}"

      request_options = {
        method: method,
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
      else
        error = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          { 'error' => response.body, 'status_code' => response.code }
        end

        raise APIError.new(error, response.code)
      end
    end

    def build_query_params(params)
      return '' if params.empty?

      query_string = params.map do |key, value|
        value = value.to_json if value.is_a?(Hash) || value.is_a?(Array)
        "#{key}=#{CGI.escape(value.to_s)}"
      end.join('&')
      "?#{query_string}"
    end
  end
end
