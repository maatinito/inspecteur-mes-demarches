# frozen_string_literal: true

module SchemaBuilders
  # Adapter SchemaBuilders::Target pour Grist.
  #
  # Grist a une hiérarchie à 4 niveaux : organisation -> workspace -> document -> table.
  # L'interface utilise la terminologie Baserow (3 niveaux : workspace -> application -> table).
  # Mapping conceptuel :
  #   - "workspace" (interface) -> workspace Grist
  #   - "application" (interface) -> document Grist (doc_id)
  #   - "table" (interface) -> table Grist
  #
  # Comme l'API Grist requiert le doc_id pour les opérations sur les colonnes,
  # le `table_id` exposé par cet adapter est un identifiant composite "doc_id:table_id"
  # afin de conserver le contexte sans modifier la signature des méthodes d'interface.
  #
  # Mapping interface -> client réel :
  #   list_workspaces            -> aplatit Client#list_organizations + Client#list_workspaces(org)
  #   list_applications(ws_id)   -> Client#get_workspace(ws_id), extrait la liste des docs
  #   list_tables(doc_id)        -> Client#list_tables(doc_id)
  #   create_table(doc_id, n, f) -> Client#create_tables(doc_id, ...)
  #   update_fields("d:t", f)    -> Client#create_columns / #update_column
  #   table_exists?(doc_id, n)   -> recherche dans Client#list_tables(doc_id)
  #   field_exists?("d:t", n)    -> recherche dans Client#list_columns(doc_id, table_id)
  class GristTarget
    include SchemaBuilders::Target

    SEPARATOR = ':'

    attr_reader :client

    def initialize(client: nil)
      @client = client || Grist::Config.client
    end

    # Aplatit la liste de tous les workspaces visibles, toutes orgs confondues.
    # TODO: optimiser si Grist::Client expose un endpoint global "list_workspaces"
    def list_workspaces
      orgs = @client.list_organizations || []
      orgs.flat_map { |org| Array(@client.list_workspaces(org['id'])) }
    end

    # Liste les "applications" (= documents Grist) d'un workspace.
    def list_applications(workspace_id)
      ws = @client.get_workspace(workspace_id) || {}
      ws['docs'] || []
    end

    # Liste les tables d'un document Grist.
    def list_tables(application_id)
      response = @client.list_tables(application_id)
      response.is_a?(Hash) ? (response['tables'] || []) : Array(response)
    end

    # Crée une table dans un document Grist avec ses colonnes initiales.
    # `fields` est un tableau de hashes au format Grist (id + fields).
    def create_table(application_id, name, fields)
      payload = {
        tables: [
          { id: name, columns: Array(fields) }
        ]
      }
      @client.create_tables(application_id, payload)
    end

    # `table_id` doit être au format composite "doc_id:table_id".
    # Met à jour les colonnes existantes et crée celles qui manquent.
    def update_fields(table_id, fields)
      doc_id, real_table_id = parse_composite_id(table_id)
      existing = list_columns_safe(doc_id, real_table_id)
      existing_ids = existing.to_set { |c| c['id'] }

      to_create = []
      Array(fields).each do |field|
        col_id = field[:id] || field['id']
        if col_id && existing_ids.include?(col_id)
          @client.update_column(doc_id, real_table_id, col_id, field[:fields] || field['fields'] || field)
        else
          to_create << field
        end
      end

      @client.create_columns(doc_id, real_table_id, { columns: to_create }) if to_create.any?
    end

    def table_exists?(application_id, name)
      tables = list_tables(application_id)
      tables.any? { |t| (t['id'] || t[:id])&.to_s == name.to_s }
    rescue Grist::APIError
      false
    end

    # `table_id` doit être au format composite "doc_id:table_id".
    def field_exists?(table_id, name)
      doc_id, real_table_id = parse_composite_id(table_id)
      columns = list_columns_safe(doc_id, real_table_id)
      columns.any? { |c| (c['id'] || c[:id])&.to_s == name.to_s }
    rescue Grist::APIError
      false
    end

    private

    def parse_composite_id(table_id)
      doc_id, real_table_id = table_id.to_s.split(SEPARATOR, 2)
      raise ArgumentError, "table_id Grist attendu au format 'doc_id:table_id', reçu #{table_id.inspect}" if doc_id.blank? || real_table_id.blank?

      [doc_id, real_table_id]
    end

    def list_columns_safe(doc_id, table_id)
      response = @client.list_columns(doc_id, table_id)
      response.is_a?(Hash) ? (response['columns'] || []) : Array(response)
    end
  end
end
