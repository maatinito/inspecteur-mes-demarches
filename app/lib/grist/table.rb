# frozen_string_literal: true

module Grist
  # Wrapper haut niveau pour interagir avec une table Grist
  # Contrairement à Baserow, les IDs de colonnes Grist sont des strings (= le nom de la colonne)
  class Table
    attr_reader :client, :doc_id, :table_id

    def initialize(client, doc_id, table_id)
      @client = client
      @doc_id = doc_id
      @table_id = table_id
      @columns = nil # Lazy loading
    end

    # Lazy loading des métadonnées colonnes
    # Retourne { "ColName" => { id: "ColName", type: "Text", isFormula: false, formula: "" } }
    def columns
      @columns ||= load_columns
    end

    # Recherche par valeur de colonne
    # Utilise le filtre JSON Grist : ?filter={"col":["value"]}
    def find_by(col, value)
      filter = { col => [value] }.to_json
      result = client.list_records(doc_id, table_id, { filter: filter })
      result['records'] || []
    end

    # Liste tous les records
    def list_records(params = {})
      client.list_records(doc_id, table_id, params)
    end

    # Ajoute des records
    def add_records(records)
      client.add_records(doc_id, table_id, records)
    end

    # Met à jour des records
    def update_records(records)
      client.update_records(doc_id, table_id, records)
    end

    # Upsert natif
    def upsert_records(records)
      client.upsert_records(doc_id, table_id, records)
    end

    # Supprime des records
    def delete_records(ids)
      client.delete_records(doc_id, table_id, ids)
    end

    private

    def load_columns
      result = client.list_columns(doc_id, table_id)
      columns_data = result['columns'] || []

      columns_data.each_with_object({}) do |col, hash|
        col_id = col['id']
        fields = col['fields'] || {}
        hash[col_id] = {
          id: col_id,
          label: fields['label'] || col_id,
          type: fields['type'] || 'Any',
          isFormula: fields['isFormula'] || false,
          formula: fields['formula'] || ''
        }
      end
    end
  end
end
