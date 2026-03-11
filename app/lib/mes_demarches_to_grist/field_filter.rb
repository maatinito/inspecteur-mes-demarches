# frozen_string_literal: true

module MesDemarchesToGrist
  # Filtre les colonnes Grist pour exclure les champs read-only (formules)
  #
  # Contrairement à Baserow qui a plusieurs types read-only (formula, lookup, rollup, count),
  # Grist utilise isFormula=true pour identifier les colonnes calculées
  class FieldFilter
    def initialize(doc_id, table_id, config_name = nil)
      @doc_id = doc_id
      @table_id = table_id
      @config_name = config_name
      @column_metadata = nil
    end

    def load_columns
      return @column_metadata if @column_metadata

      table = Grist::Config.table(@doc_id, @table_id, @config_name)
      columns = table.columns

      @column_metadata = columns.transform_values do |col_data|
        {
          id: col_data[:id],
          type: col_data[:type],
          isFormula: col_data[:isFormula],
          readonly: col_data[:isFormula] == true
        }
      end

      @column_metadata
    end

    def filter_syncable_fields(data)
      load_columns unless @column_metadata

      data.select do |field_name, _value|
        col_meta = @column_metadata[field_name]
        next false unless col_meta

        !col_meta[:readonly]
      end
    end
  end
end
