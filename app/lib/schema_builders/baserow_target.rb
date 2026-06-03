# frozen_string_literal: true

module SchemaBuilders
  # Adapter SchemaBuilders::Target pour Baserow.
  #
  # Délègue aux méthodes existantes de Baserow::StructureClient.
  #
  # Mapping interface -> client réel :
  #   list_workspaces              -> StructureClient#list_workspaces
  #   list_applications(ws_id)     -> StructureClient#list_applications(ws_id)
  #   list_tables(app_id)          -> StructureClient#list_tables(database_id)
  #   create_table(app_id, n, f)   -> StructureClient#create_table(application_id, table_data)
  #                                   puis StructureClient#create_field pour chaque champ
  #   update_fields(table_id, f)   -> StructureClient#create_field / #update_field selon présence
  #   table_exists?(app_id, name)  -> recherche dans #list_tables(application_id)
  #   field_exists?(table_id, n)   -> StructureClient#field_exists?(table_id, name)
  class BaserowTarget
    include SchemaBuilders::Target

    attr_reader :client

    def initialize(client: nil)
      @client = client || Baserow::StructureClient.new
    end

    def list_workspaces
      @client.list_workspaces
    end

    # Le schema builder ne peut synchroniser que vers des "databases" Baserow
    # (qui contiennent des tables). On exclut les "builder" (UI builder sans
    # tables) et "dashboard" qui pollueraient le dropdown Application.
    def list_applications(workspace_id)
      Array(@client.list_applications(workspace_id)).select do |app|
        (app['type'] || app[:type]).to_s == 'database'
      end
    end

    def list_tables(application_id)
      @client.list_tables(application_id)
    end

    # Crée une table dans une application Baserow, puis ajoute les champs un par un.
    # `fields` est un tableau de hashes au format Baserow create_field (cf. SchemaBuilder).
    def create_table(application_id, name, fields)
      table = @client.create_table(application_id, { name: name })
      table_id = table['id']
      Array(fields).each { |field_data| @client.create_field(table_id, field_data) }
      table
    end

    # Met à jour (ou crée si absent) chaque champ. Chaque entrée de `fields` est un hash
    # qui doit contenir au minimum `:name` (ou `'name'`) et les données Baserow pour create_field /
    # update_field.
    def update_fields(table_id, fields)
      Array(fields).map do |field_data|
        name = field_data[:name] || field_data['name']
        existing = @client.get_field_by_name(table_id, name) if name
        if existing
          @client.update_field(existing['id'], field_data)
        else
          @client.create_field(table_id, field_data)
        end
      end
    end

    def table_exists?(application_id, name)
      tables = @client.list_tables(application_id) || []
      tables.any? { |t| t['name']&.casecmp(name.to_s)&.zero? }
    rescue Baserow::APIError
      false
    end

    def field_exists?(table_id, name)
      @client.field_exists?(table_id, name)
    end

    # Liste les champs d'une table (utilisé notamment par SchemaBuilders::Differ).
    # Retourne un tableau de hashes Baserow brut (clés strings : 'name', 'type', etc.).
    def get_table_fields(table_id)
      @client.get_table_fields(table_id)
    end
  end
end
