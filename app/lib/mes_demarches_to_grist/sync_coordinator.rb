# frozen_string_literal: true

module MesDemarchesToGrist
  # Coordonne la synchronisation d'une démarche vers Grist
  #
  # Pipeline : extract → filter → upload files → upsert → sync blocs
  #
  # Différences clés avec Baserow SyncCoordinator :
  # - Config prend doc_id + table_id (Grist scope les tables par document)
  # - Upsert natif au lieu de find→create/update
  # - Blocs répétables : table liée via Ref:MainTable + formule Python
  class SyncCoordinator
    attr_reader :demarche_number, :grist_config, :options

    def initialize(demarche_number, grist_config, options = {})
      @demarche_number = demarche_number
      @grist_config = grist_config.is_a?(Hash) ? grist_config.deep_stringify_keys : grist_config
      @options = options.is_a?(Hash) ? options.deep_stringify_keys : options
      @schema_ensured = false

      @doc_id = @grist_config['doc_id']
      @table_id = @grist_config['table_id']

      @main_table = get_table(@doc_id, @table_id)
      @main_field_filter = FieldFilter.new(@doc_id, @table_id, @grist_config['token_config'])
      @main_field_metadata = @main_table.columns # { col_id => {id, label, type, ...} }

      # Mapping label → col_id pour convertir les clés DataExtractor → Grist
      @label_to_col_id = {}
      @field_metadata_by_label = {}
      @main_field_metadata.each do |col_id, meta|
        label = meta[:label]
        @label_to_col_id[label] = col_id
        @field_metadata_by_label[label] = meta
      end

      @dossier_col_id = @label_to_col_id['Dossier'] || 'Dossier'
    end

    def sync_dossier(dossier)
      ensure_schema unless @schema_ensured

      # 1. Récupérer le record existant
      existing_record = find_existing_record(dossier.number)

      # 2. Enrichir les métadonnées des attachments existants (évite les re-uploads)
      attachment_metadata = existing_record ? fetch_attachment_metadata(existing_record) : {}

      # 3. Extraire les données du dossier (clés = labels)
      data_extractor = DataExtractor.new(@field_metadata_by_label, @options, attachment_metadata: attachment_metadata)
      extracted_data = data_extractor.extract_all(dossier)

      # 4. Convertir les clés labels → col_ids Grist
      main_data = convert_labels_to_col_ids(extracted_data[:main_table])

      # 5. Filtrer les champs read-only
      syncable_data = @main_field_filter.filter_syncable_fields(main_data)

      # 6. Traiter les uploads de fichiers (seuls les nouveaux sont uploadés)
      syncable_data = process_file_uploads(syncable_data)

      # 7. Upsert dans la table principale
      upserter = RowUpserter.new(@main_table, @options, @main_field_metadata, dossier_col_id: @dossier_col_id)
      main_record_id = upserter.upsert_row(dossier.number, syncable_data, existing_record: existing_record)

      # 8. Synchroniser les blocs répétables
      sync_repetable_blocks(dossier.number, extracted_data[:repetable_blocks], main_record_id)

      Rails.logger.info "GristSync: Dossier #{dossier.number} synchronisé avec succès"
    end

    private

    def ensure_schema
      @schema_ensured = true
    end

    # Récupère les métadonnées (fileName, fileSize) des attachments existants
    # pour éviter de re-télécharger/re-uploader les fichiers inchangés.
    # Retourne { label => [{id:, fileName:, fileSize:}, ...] }
    def fetch_attachment_metadata(existing_record)
      metadata = {}
      fields = existing_record['fields'] || {}
      client = @main_table.client

      @main_field_metadata.each do |col_id, meta|
        next unless meta[:type] == 'Attachments'

        attachment_value = fields[col_id]
        next unless attachment_value.is_a?(Array) && attachment_value.first == 'L'

        ids = attachment_value[1..] # Skip le 'L' prefix
        label = meta[:label]

        metadata[label] = ids.filter_map do |att_id|
          info = client.get_attachment_metadata(@doc_id, att_id)
          { id: att_id, fileName: info['fileName'], fileSize: info['fileSize'] }
        rescue Grist::APIError => e
          Rails.logger.warn "GristSync: Erreur metadata attachment #{att_id}: #{e.message}"
          nil
        end
      end

      metadata
    end

    # Traite les uploads de fichiers vers Grist
    # Convertit les {url:, visible_name:} en ["L", attachment_id]
    # rubocop:disable Metrics/MethodLength
    def process_file_uploads(data)
      file_uploader = Grist::FileUploader.new(
        Grist::Config.client(@grist_config['token_config']),
        @doc_id
      )

      data.each do |field_name, value|
        next unless @main_field_metadata[field_name]&.dig(:type) == 'Attachments'
        next if value.blank? || !value.is_a?(Array)

        attachment_ids = value.filter_map do |file_data|
          next unless file_data.is_a?(Hash)

          if file_data[:existing_id]
            # Fichier inchangé : réutiliser l'attachment_id existant
            file_data[:existing_id]
          elsif file_data[:url]
            # Nouveau fichier : télécharger et uploader
            visible_name = file_data[:visible_name] || 'fichier'
            attachment_id = file_uploader.download_and_upload(file_data[:url], visible_name)

            unless attachment_id
              Rails.logger.warn "GristSync: Échec upload fichier #{visible_name} pour champ #{field_name}"
              next
            end

            attachment_id
          end
        end

        if attachment_ids.empty?
          data.delete(field_name)
        else
          # Format Grist pour Attachments : ["L", id1, id2, ...]
          data[field_name] = ['L'] + attachment_ids
        end
      end

      data
    rescue StandardError => e
      Rails.logger.error "GristSync: Erreur traitement uploads fichiers: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
    # rubocop:enable Metrics/MethodLength

    def sync_repetable_blocks(dossier_number, blocks_data, main_record_id)
      return if blocks_data.blank?

      # Découvrir les tables du document
      available_tables = discover_document_tables

      blocks_data.each do |block_name, rows|
        # Chercher la table par nom exact ou par ID parameterizé
        table_id = available_tables[block_name] || available_tables[block_name.parameterize(separator: '_')]

        unless table_id
          Rails.logger.debug "GristSync: Table '#{block_name}' non trouvée dans le document Grist, skip du bloc répétable"
          next
        end

        Rails.logger.info "GristSync: Synchronisation bloc répétable '#{block_name}' vers table #{table_id}"
        sync_block_rows(dossier_number, table_id, rows, main_record_id)
      end
    end

    def discover_document_tables
      result = @main_table.client.list_tables(@doc_id)
      tables = result['tables'] || []

      tables.to_h do |table|
        [table['id'], table['id']]
      end
    rescue StandardError => e
      Rails.logger.error "GristSync: Erreur découverte tables: #{e.message}"
      raise
    end

    def sync_block_rows(dossier_number, table_id, rows, main_record_id)
      return unless main_record_id

      block_table = get_table(@doc_id, table_id)
      block_columns = block_table.columns

      # Mapping label → col_id pour ce bloc
      block_label_to_col_id = {}
      block_columns.each { |col_id, meta| block_label_to_col_id[meta[:label]] = col_id }
      block_dossier_col_id = block_label_to_col_id['Dossier'] || 'Dossier'
      block_ligne_col_id = block_label_to_col_id['Ligne'] || 'Ligne'

      existing_records = block_table.find_by(block_dossier_col_id, main_record_id)

      # Convertir et synchroniser chaque row via upsert
      rows.each do |row_data|
        converted = convert_block_row(row_data, block_label_to_col_id)
        converted[block_dossier_col_id] = main_record_id
        upsert_block_row(converted, block_table, block_dossier_col_id, block_ligne_col_id, dossier_number)
      end

      # Supprimer les orphelins
      supprimer_orphelins = @options.key?('supprimer_orphelins') ? @options['supprimer_orphelins'] : true
      delete_orphan_records(block_table, existing_records, rows, block_ligne_col_id, dossier_number) if supprimer_orphelins
    rescue StandardError => e
      Rails.logger.error "GristSync: Erreur synchro bloc répétable (table #{table_id}): #{e.message}"
      raise unless @options['continuer_si_erreur']
    end

    def convert_block_row(row_data, block_label_to_col_id)
      row_data.each_with_object({}) do |(key, value), result|
        col_id = block_label_to_col_id[key] || key
        result[col_id] = value
      end
    end

    def upsert_block_row(row_data, block_table, dossier_col_id, ligne_col_id, dossier_number)
      ligne = row_data[ligne_col_id]

      record = {
        require: { dossier_col_id => row_data[dossier_col_id], ligne_col_id => ligne },
        fields: row_data
      }
      block_table.upsert_records([record])

      Rails.logger.debug "GristSync: Bloc ligne #{ligne} upserted (dossier #{dossier_number})"
    end

    def delete_orphan_records(block_table, existing_records, current_rows, ligne_col_id, dossier_number)
      current_lignes = current_rows.to_set { |r| r['Ligne'] }

      orphan_ids = existing_records.filter_map do |record|
        existing_ligne = record.dig('fields', ligne_col_id)
        next if current_lignes.include?(existing_ligne)

        record['id']
      end

      return if orphan_ids.empty?

      block_table.delete_records(orphan_ids)
      Rails.logger.info "GristSync: #{orphan_ids.length} row(s) orpheline(s) supprimée(s) (dossier #{dossier_number})"
    end

    def convert_labels_to_col_ids(data)
      data.each_with_object({}) do |(key, value), result|
        col_id = @label_to_col_id[key] || key
        result[col_id] = value
      end
    end

    def find_existing_record(dossier_number)
      records = @main_table.find_by(@dossier_col_id, dossier_number)
      records.first
    rescue StandardError => e
      Rails.logger.error "GristSync: Erreur recherche record existant: #{e.message}"
      raise
    end

    def get_table(doc_id, table_id)
      Grist::Config.table(doc_id, table_id, @grist_config['token_config'])
    end
  end
end
