# frozen_string_literal: true

module BaserowSync
  # Coordonne la synchronisation d'une démarche vers Baserow
  #
  # Responsabilités:
  # - Initialiser/mettre à jour le schéma Baserow (première fois)
  # - Coordonner l'extraction, le filtrage et l'upsert des données
  # - Gérer les blocs répétables (tables liées)
  class SyncCoordinator
    attr_reader :demarche_number, :baserow_config, :options

    def initialize(demarche_number, baserow_config, options = {})
      @demarche_number = demarche_number
      @baserow_config = baserow_config.is_a?(Hash) ? baserow_config.deep_stringify_keys : baserow_config
      @options = options.is_a?(Hash) ? options.deep_stringify_keys : options
      @schema_ensured = false
    end

    def sync_dossier(dossier)
      ensure_schema unless @schema_ensured

      # 1. Charger les métadonnées des champs Baserow
      field_filter = FieldFilter.new(
        @baserow_config['table_id'],
        @baserow_config['token_config']
      )
      field_metadata = field_filter.load_baserow_fields

      # 2. Récupérer la row existante pour détecter les fichiers déjà présents
      main_table = get_table(@baserow_config['table_id'])
      existing_row = find_existing_row(main_table, dossier.number)

      # 3. Extraire les données du dossier
      data_extractor = DataExtractor.new(field_metadata, @options)
      extracted_data = data_extractor.extract_all(dossier, existing_row)

      # 4. Filtrer les champs read-only
      syncable_data = field_filter.filter_syncable_fields(extracted_data[:main_table])

      # 5. Upsert dans la table principale
      upserter = RowUpserter.new(main_table, @options)
      upserter.upsert_row(dossier.number, syncable_data)

      # 6. Synchroniser les blocs répétables
      sync_repetable_blocks(dossier.number, extracted_data[:repetable_blocks]) if @options['include_repetable_blocks']

      Rails.logger.info "BaserowSync: Dossier #{dossier.number} synchronisé avec succès"
    end

    private

    def ensure_schema
      # TODO: Implémenter si nécessaire (SchemaBuilder)
      # Pour l'instant, on suppose que les tables existent déjà
      @schema_ensured = true
    end

    def sync_repetable_blocks(dossier_number, blocks_data)
      return if blocks_data.blank?

      blocks_data.each do |block_name, rows|
        # Trouver la config du bloc
        block_config = @options['repetable_blocks']&.find { |b| b['table_name'] == block_name }
        next unless block_config && block_config['table_id']

        sync_block_rows(dossier_number, block_config['table_id'], rows)
      end
    end

    def sync_block_rows(dossier_number, table_id, rows)
      block_table = get_table(table_id)
      RowUpserter.new(block_table, @options)

      # Récupérer les rows existantes pour ce dossier
      existing_rows = block_table.search('Dossier', dossier_number.to_s)

      # Synchroniser chaque row
      rows.each do |row_data|
        bloc_value = "#{dossier_number}-#{row_data['Ligne']}"
        existing = existing_rows.find { |r| r['Bloc'] == bloc_value }

        if existing
          # Update existante
          block_table.update_row(existing['id'], row_data)
        else
          # Nouvelle row
          block_table.create_row(row_data)
        end
      end

      # Optionnel: supprimer les rows qui n'existent plus dans le dossier
      delete_orphan_rows(existing_rows, rows, dossier_number) if @options['delete_orphans']
    rescue StandardError => e
      Rails.logger.error "BaserowSync: Erreur synchro bloc répétable (table #{table_id}): #{e.message}"
      raise unless @options['continue_on_error']
    end

    def delete_orphan_rows(existing_rows, current_rows, dossier_number)
      current_blocs = current_rows.map { |r| "#{dossier_number}-#{r['Ligne']}" }
      existing_rows.each do |row|
        next if current_blocs.include?(row['Bloc'])

        block_table = get_table(row['table_id'])
        block_table.delete_row(row['id'])
        Rails.logger.info "BaserowSync: Row orpheline supprimée: #{row['Bloc']}"
      end
    end

    def find_existing_row(table, dossier_number)
      results = table.search('Dossier', dossier_number.to_s)
      results.first
    rescue StandardError => e
      Rails.logger.warn "BaserowSync: Erreur recherche row existante: #{e.message}"
      nil
    end

    def get_table(table_id)
      Baserow::Config.table(
        table_id,
        @baserow_config['token_config']
      )
    end
  end
end
