# frozen_string_literal: true

module SchemaBuilders
  # Filtre les champs d'une cible (Baserow ou Grist) pour exclure les champs
  # read-only (formules, lookups, etc.) lors d'une synchronisation depuis
  # Mes-Démarches.
  #
  # Consolide MesDemarchesToBaserow::FieldFilter et MesDemarchesToGrist::FieldFilter.
  # Les deux filtres sont substantiellement différents (sources, schéma de métadonnées,
  # critères de read-only) ; cette classe factorise l'interface commune
  # `#filter_syncable_fields(data)` et délègue le chargement et la détection
  # read-only à des sous-classes spécialisées via la factory `.for`.
  #
  # Usage:
  #   filter = SchemaBuilders::FieldFilter.for(:baserow, table_id: 42, token_config: 'tftn')
  #   filter = SchemaBuilders::FieldFilter.for(:grist, doc_id: 'doc', table_id: 'Contacts')
  #   filter.filter_syncable_fields({ 'Nom' => 'X', 'Calcul' => 1 })
  class FieldFilter
    def self.for(target, **)
      case target
      when :baserow then BaserowFieldFilter.new(**)
      when :grist   then GristFieldFilter.new(**)
      else
        raise ArgumentError, "unknown target #{target.inspect}"
      end
    end

    # Filtre un hash de données pour ne garder que les champs syncables
    # (présents dans la cible et non read-only).
    def filter_syncable_fields(data)
      load_metadata unless @metadata
      data.select { |field_name, _| syncable?(field_name) }
    end

    # À surcharger : charge et mémoize @metadata (hash field_name -> infos).
    def load_metadata
      raise NotImplementedError
    end

    # À surcharger : true si le champ est syncable côté cible.
    def syncable?(_field_name)
      raise NotImplementedError
    end
  end

  # Filtre Baserow : exclut les types read-only (formula, lookup, rollup, count, etc.).
  class BaserowFieldFilter < FieldFilter
    READONLY_TYPES = %w[formula lookup rollup count created_on last_modified].freeze

    attr_reader :table_id, :token_config

    def initialize(table_id:, token_config: nil)
      super()
      @table_id = table_id
      @token_config = token_config
      @metadata = nil
    end

    def load_metadata
      return @metadata if @metadata

      client = Baserow::Config.client(@token_config)
      fields = client.list_fields(@table_id)

      @metadata = {}
      fields.each do |field|
        @metadata[field['name']] = {
          'id' => field['id'],
          'type' => field['type'],
          'config' => field,
          'readonly' => readonly_field?(field)
        }
      end

      @metadata
    end

    # Compatibilité avec MesDemarchesToBaserow::FieldFilter#load_baserow_fields
    alias load_baserow_fields load_metadata

    def readonly_field?(field)
      READONLY_TYPES.include?(field['type'])
    end

    def syncable?(field_name)
      meta = @metadata[field_name]
      return false unless meta

      !meta['readonly']
    end
  end

  # Filtre Grist : exclut les colonnes calculées (isFormula == true).
  class GristFieldFilter < FieldFilter
    attr_reader :doc_id, :table_id, :config_name

    def initialize(doc_id:, table_id:, config_name: nil)
      super()
      @doc_id = doc_id
      @table_id = table_id
      @config_name = config_name
      @metadata = nil
    end

    def load_metadata
      return @metadata if @metadata

      table = Grist::Config.table(@doc_id, @table_id, @config_name)
      columns = table.columns

      @metadata = columns.transform_values do |col_data|
        {
          id: col_data[:id],
          type: col_data[:type],
          isFormula: col_data[:isFormula],
          readonly: col_data[:isFormula] == true
        }
      end

      @metadata
    end

    # Compatibilité avec MesDemarchesToGrist::FieldFilter#load_columns
    alias load_columns load_metadata

    def syncable?(field_name)
      meta = @metadata[field_name]
      return false unless meta

      !meta[:readonly]
    end
  end
end
