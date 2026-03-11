# frozen_string_literal: true

module MesDemarchesToGrist
  # Crée les tables liées pour les blocs répétables dans un document Grist
  #
  # Différences avec Baserow :
  # - Les tables sont créées dans le même document (pas besoin d'application_id)
  # - Lien via Ref:MainTable au lieu de link_row
  # - Champ Bloc = formule Python : str($Dossier.Dossier) + '-' + str($Ligne)
  class RepetableBlockBuilder
    class BlockError < StandardError; end

    attr_reader :demarche_number, :doc_id, :main_table_id, :report

    def initialize(demarche_number, doc_id, main_table_id)
      @demarche_number = demarche_number
      @doc_id = doc_id
      @main_table_id = main_table_id
      @client = Grist::Config.client
      @type_mapper = TypeMapper.new
      @created_tables = {}
      @report = {
        tables_created: [],
        tables_updated: [],
        fields_created: [],
        link_fields_created: [],
        errors: []
      }
    end

    def preview
      demarche = fetch_demarche
      revision = demarche.draft_revision || demarche.published_revision

      repetable_blocks = extract_repetable_blocks(revision)

      {
        total_blocks: repetable_blocks.length,
        blocks: repetable_blocks.map do |block|
          {
            champ_id: block.id,
            label: block.label,
            suggested_table_name: sanitize_table_id(block.label),
            fields_count: block.champ_descriptors.length,
            fields: block.champ_descriptors.map { |champ| format_field_info(champ) }
          }
        end
      }
    end

    def build!(blocks_config)
      validate_main_table!

      blocks_config.each do |block_config|
        create_or_update_repetable_table(block_config)
      end

      @report
    end

    private

    def fetch_demarche
      result = MesDemarches.query(
        MesDemarches::Queries::DemarcheRevision,
        variables: { demarche: @demarche_number }
      )

      raise BlockError, "Erreur d'accès à la démarche: #{result.errors.map(&:message).join(', ')}" if result.errors.any?
      raise BlockError, "Démarche #{@demarche_number} introuvable" if result.data&.demarche.nil?

      result.data.demarche
    end

    def extract_repetable_blocks(revision)
      all_descriptors = (revision.champ_descriptors || []) + (revision.annotation_descriptors || [])
      all_descriptors.select { |descriptor| descriptor.__typename == 'RepetitionChampDescriptor' }
    end

    def format_field_info(champ)
      {
        label: champ.label,
        type: champ.__typename,
        supported: TypeMapper.supported_type?(champ.__typename)
      }
    end

    def validate_main_table!
      tables = @client.list_tables(@doc_id)
      table_ids = (tables['tables'] || []).map { |t| t['id'] }
      raise BlockError, "Table principale #{@main_table_id} introuvable dans le document" unless table_ids.include?(@main_table_id)

      # Vérifier qu'il y a une colonne Dossier
      columns = @client.list_columns(@doc_id, @main_table_id)
      col_ids = (columns['columns'] || []).map { |c| c['id'] }
      raise BlockError, 'La table principale doit avoir une colonne "Dossier"' unless col_ids.include?('Dossier')
    end

    def create_or_update_repetable_table(block_config)
      champ_id = block_config['champ_id']
      table_name = block_config['table_name']

      demarche = fetch_demarche
      revision = demarche.draft_revision || demarche.published_revision
      repetable_blocks = extract_repetable_blocks(revision)

      block = repetable_blocks.find { |b| b.id == champ_id }
      raise BlockError, "Bloc #{champ_id} introuvable" unless block

      table_id = sanitize_table_id(table_name)
      existing_table = find_table_by_id(table_id)

      if existing_table
        update_repetable_table(table_id, table_name, block)
      else
        create_repetable_table(table_id, table_name, block)
      end
    end

    def find_table_by_id(table_id)
      return @created_tables[table_id] if @created_tables.key?(table_id)

      tables = @client.list_tables(@doc_id)
      (tables['tables'] || []).find { |t| t['id'] == table_id }
    end

    # rubocop:disable Metrics/MethodLength
    def create_repetable_table(table_id, table_name, block)
      # Créer la table avec les colonnes de structure
      table_data = {
        tables: [{
          id: table_id,
          columns: [
            { id: 'Ligne', fields: { label: 'Ligne', type: 'Integer', isFormula: false } },
            { id: 'Dossier', fields: { label: 'Dossier', type: "Ref:#{@main_table_id}", isFormula: false } },
            { id: 'Bloc', fields: {
              label: 'Bloc', type: 'Text',
              isFormula: true,
              formula: "str($Dossier.Dossier) + '-' + str($Ligne)"
            } }
          ]
        }]
      }

      @client.create_tables(@doc_id, table_data)
      @created_tables[table_id] = { 'id' => table_id }

      @report[:tables_created] << {
        name: table_name,
        id: table_id,
        block_label: block.label
      }

      @report[:link_fields_created] << {
        name: 'Dossier',
        from_table: table_id,
        to_table: @main_table_id
      }

      # Créer les colonnes des champs du bloc
      create_block_columns(table_id, block)
    rescue StandardError => e
      error_msg = "Erreur création table #{table_name}: #{e.message}"
      Rails.logger.error "RepetableBlockBuilder: #{error_msg}"
      @report[:errors] << error_msg
    end
    # rubocop:enable Metrics/MethodLength

    def update_repetable_table(table_id, table_name, block)
      @report[:tables_updated] << {
        name: table_name,
        id: table_id,
        block_label: block.label
      }

      create_block_columns(table_id, block)
    rescue StandardError => e
      error_msg = "Erreur mise à jour table #{table_name}: #{e.message}"
      Rails.logger.error "RepetableBlockBuilder: #{error_msg}"
      @report[:errors] << error_msg
    end

    def create_block_columns(table_id, block) # rubocop:disable Metrics/MethodLength
      existing_columns = @client.list_columns(@doc_id, table_id)
      existing_col_ids = Set.new((existing_columns['columns'] || []).map { |c| c['id'] })

      columns_to_add = []

      block.champ_descriptors.each do |champ|
        field_type = champ.__typename
        next if TypeMapper.should_ignore_type?(field_type)
        next unless TypeMapper.supported_type?(field_type)

        col_id = sanitize_table_id(champ.label)
        next if existing_col_ids.include?(col_id)

        mapping = @type_mapper.map_field_type(field_type, champ.to_h)
        col_data = {
          id: col_id,
          fields: { label: champ.label, type: mapping[:type], isFormula: false }
        }

        col_data[:fields][:widgetOptions] = mapping[:config][:widgetOptions].to_json if mapping[:config]&.key?(:widgetOptions)

        columns_to_add << col_data
      rescue TypeMapper::UnsupportedTypeError
        # Skip silencieux
      end

      return if columns_to_add.empty?

      @client.create_columns(@doc_id, table_id, { columns: columns_to_add })

      columns_to_add.each do |col|
        @report[:fields_created] << {
          table: table_id,
          name: col[:fields][:label],
          type: col[:fields][:type]
        }
      end
    rescue Grist::APIError => e
      @report[:errors] << "Erreur création colonnes dans #{table_id}: #{e.message}"
    end

    # Convertit un nom en ID Grist valide
    def sanitize_table_id(name)
      id = name.to_s.parameterize(separator: '_')
      id = "t_#{id}" if id.match?(/\A\d/)
      id
    end
  end
end
