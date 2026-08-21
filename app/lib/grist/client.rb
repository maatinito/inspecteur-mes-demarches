# frozen_string_literal: true

require 'typhoeus'
require 'json'

module Grist
  # Client REST pour l'API Grist (Data + Structure)
  # Contrairement à Baserow, Grist utilise une seule clé API (Bearer) pour tout.
  class Client
    attr_reader :base_url

    # Délai d'une requête, en secondes. Les 30 s d'origine suffisaient tant que
    # les réponses restaient petites : sur une table de plusieurs dizaines de
    # milliers de lignes, `list_records` rend plus de 2 Mo et curl coupe le
    # transfert en cours de route — avec un code 200 et un corps incomplet, voir
    # handle_response. Surchargeable pour un document particulièrement volumineux.
    TIMEOUT_DEFAUT = 120

    def self.timeout
      ENV.fetch('GRIST_TIMEOUT', TIMEOUT_DEFAUT).to_i
    end

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

    # Interroge un document en SQL (SELECT seulement, Grist refuse le reste).
    # GET /api/docs/{docId}/sql?q=...
    #
    # Utile quand `list_records` est disproportionné : il rend toutes les colonnes
    # de toutes les lignes — 25 Mo et deux minutes sur la table Substances des
    # pesticides — là où trois colonnes suffisent souvent. Une projection SQL y
    # répond en 1,6 Mo et deux secondes.
    #
    # `timeout_ms` est le délai côté Grist, distinct de celui du transfert.
    def sql(doc_id, query, timeout_ms: 8000)
      response = make_request(:get, "/api/docs/#{doc_id}/sql#{build_query_params(q: query, timeout: timeout_ms)}")
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

    # Met à jour une colonne existante.
    # Grist n'expose PAS de route PUT /columns/{colId} : la modification d'une
    # colonne passe par un PATCH sur la collection, l'id de colonne étant porté
    # dans le corps. (L'ancienne route PUT/{colId} renvoyait systématiquement
    # "not found" dès qu'on re-synchronisait une table existante.)
    # PATCH /api/docs/{docId}/tables/{tableId}/columns
    #   body: { columns: [{ id: <colId>, fields: {...} }] }
    def update_column(doc_id, table_id, col_id, fields)
      body = { columns: [{ id: col_id, fields: fields }] }
      response = make_request(:patch, "/api/docs/#{doc_id}/tables/#{table_id}/columns", body: body.to_json)
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
        timeout: self.class.timeout
      }

      request_options.merge!(options)
      Typhoeus::Request.new(url, request_options).run
    end

    def handle_response(response)
      case response.code
      when 200, 201, 202
        parser_succes(response)
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

    # Un transfert coupé se présente comme un succès : curl rend le code HTTP reçu
    # avant la coupure, donc 200, avec un corps tronqué. `JSON.parse` levait alors
    # une JSON::ParserError nue — « unexpected end of input », sans indiquer ni la
    # requête ni la cause. On la traduit en APIError explicite : la troncature est
    # un incident de transport, pas une réponse mal formée par Grist.
    def parser_succes(response)
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      taille = response.body.to_s.bytesize
      raise APIError.new(
        { 'error' => "Réponse Grist illisible (#{taille} octets reçus) : #{e.message}. " \
                     "Probable transfert interrompu — relever GRIST_TIMEOUT (actuel #{self.class.timeout} s) " \
                     'ou réduire le volume demandé.' },
        response.code
      )
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
