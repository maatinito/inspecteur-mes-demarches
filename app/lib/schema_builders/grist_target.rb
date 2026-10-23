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
    # Id de la colonne numéro de dossier, référencé par les formules des blocs.
    DOSSIER_COL_ID = 'Dossier'

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
      response = @client.create_tables(application_id, payload)
      # L'API Grist renvoie { "tables" => [{ "id" => "<tableId réel>" }] } ;
      # on normalise vers { 'id' => ... } pour s'aligner sur BaserowTarget et
      # permettre au builder d'extraire l'id de la table créée.
      created = Array(response.is_a?(Hash) ? (response['tables'] || response[:tables]) : response).first || {}
      { 'id' => created['id'] || created[:id] }
    end

    # Grist requiert un id composite "doc_id:table_id" pour les opérations sur
    # les colonnes (cf. doc de classe). On le reconstruit depuis le doc et l'id nu.
    def table_ref(application_id, table_id)
      "#{application_id}#{SEPARATOR}#{table_id}"
    end

    # `table_id` doit être au format composite "doc_id:table_id".
    # Met à jour les colonnes existantes et crée celles qui manquent.
    #
    # L'id réel d'une colonne peut différer de l'id assaini : Grist tient les ids
    # pour uniques sans égard à la casse et renomme l'id d'une colonne liée à son
    # libellé. On retrouve donc la colonne par id exact, puis par id sans casse,
    # puis par libellé — sinon chaque build recrée une copie suffixée (Dossier2).
    # Seul l'id de la colonne Dossier est rétabli s'il ne diffère que par la
    # casse : les formules des tables de blocs référencent `$Dossier.Dossier`.
    # Les autres ids ne sont jamais renommés (formules écrites par le service).
    def update_fields(table_id, fields)
      doc_id, real_table_id = parse_composite_id(table_id)
      existing = list_columns_safe(doc_id, real_table_id)

      to_create = []
      Array(fields).each do |field|
        col_id = field[:id] || field['id']
        attributes = field[:fields] || field['fields'] || field
        existing_id = find_existing_column_id(existing, col_id, attributes[:label] || attributes['label'])
        if existing_id
          attributes = attributes.merge(colId: col_id) if col_id == DOSSIER_COL_ID && existing_id != col_id
          @client.update_column(doc_id, real_table_id, existing_id, attributes)
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

    # Liste les colonnes d'une table Grist (utilisé notamment par SchemaBuilders::Differ).
    # `table_id` doit être au format composite "doc_id:table_id".
    # Retourne un tableau de hashes normalisés au format { 'name' => ..., 'type' => ... }
    # pour rester compatible avec la convention BaserowTarget.
    #
    # `name` est le LIBELLÉ de la colonne (`fields.label`), pas son id interne :
    # le Differ apparie les champs sur le libellé Mes-Démarches. Sans ça, l'id
    # assaini ('nom') ne matche jamais le libellé ('Nom') → tout en « à créer ».
    def get_table_fields(table_id)
      doc_id, real_table_id = parse_composite_id(table_id)
      columns = list_columns_safe(doc_id, real_table_id)
      columns.map do |c|
        fields = c['fields'] || c[:fields] || {}
        label = fields['label'] || fields[:label]
        {
          'name' => (label.presence || c['id'] || c[:id]).to_s,
          'type' => (fields['type'] || fields[:type]).to_s
        }
      end
    end

    # `table_id` doit être au format composite "doc_id:table_id".
    # Apparie sur le libellé (`fields.label`) ou, à défaut, l'id de colonne.
    def field_exists?(table_id, name)
      doc_id, real_table_id = parse_composite_id(table_id)
      columns = list_columns_safe(doc_id, real_table_id)
      columns.any? do |c|
        fields = c['fields'] || c[:fields] || {}
        label = fields['label'] || fields[:label]
        label.to_s == name.to_s || (c['id'] || c[:id])&.to_s == name.to_s
      end
    rescue Grist::APIError
      false
    end

    private

    def parse_composite_id(table_id)
      doc_id, real_table_id = table_id.to_s.split(SEPARATOR, 2)
      raise ArgumentError, "table_id Grist attendu au format 'doc_id:table_id', reçu #{table_id.inspect}" if doc_id.blank? || real_table_id.blank?

      [doc_id, real_table_id]
    end

    def find_existing_column_id(columns, col_id, label)
      ids = columns.map { |c| (c['id'] || c[:id]).to_s }
      return col_id if col_id && ids.include?(col_id.to_s)

      by_case = col_id && ids.find { |id| id.casecmp?(col_id.to_s) }
      return by_case if by_case
      return nil if label.blank?

      match = columns.find { |c| (c['fields'] || c[:fields] || {}).then { |f| f['label'] || f[:label] }.to_s == label.to_s }
      match && (match['id'] || match[:id]).to_s
    end

    def list_columns_safe(doc_id, table_id)
      response = @client.list_columns(doc_id, table_id)
      response.is_a?(Hash) ? (response['columns'] || []) : Array(response)
    end
  end
end
