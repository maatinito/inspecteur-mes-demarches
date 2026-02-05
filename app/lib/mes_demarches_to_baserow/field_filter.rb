# frozen_string_literal: true

module MesDemarchesToBaserow
  # Filtre les champs Baserow pour exclure les champs read-only
  #
  # Responsabilités:
  # - Charger les métadonnées des champs Baserow
  # - Identifier les champs read-only (formula, lookup, rollup, count)
  # - Filtrer les données extraites pour ne garder que les champs syncables
  class FieldFilter
    READONLY_TYPES = %w[formula lookup rollup count created_on last_modified].freeze

    def initialize(table_id, token_config = nil)
      @table_id = table_id
      @token_config = token_config
      @field_metadata = nil
    end

    def load_baserow_fields
      return @field_metadata if @field_metadata

      table # Ensure table exists
      structure_client = Baserow::StructureClient.new(@token_config)
      fields = structure_client.get_table_fields(@table_id)

      @field_metadata = {}
      fields.each do |field|
        @field_metadata[field['name']] = {
          'id' => field['id'],
          'type' => field['type'],
          'config' => field,
          'readonly' => readonly_field?(field)
        }
      end

      @field_metadata
    end

    def filter_syncable_fields(data)
      load_baserow_fields unless @field_metadata

      data.select do |field_name, _value|
        field_meta = @field_metadata[field_name]
        next false unless field_meta

        !field_meta['readonly']
      end
    end

    def readonly_field?(field)
      READONLY_TYPES.include?(field['type'])
    end

    private

    def table
      Baserow::Config.table(@table_id, @token_config)
    end
  end
end
