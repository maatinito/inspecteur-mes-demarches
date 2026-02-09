# frozen_string_literal: true

module MesDemarchesToBaserow
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

      # Initialiser les objets et caches qui seront réutilisés pour tous les dossiers
      @main_table = get_table(@baserow_config['table_id'])
      @main_field_filter = FieldFilter.new(@baserow_config['table_id'], @baserow_config['token_config'])
      @main_field_metadata = build_field_metadata(@main_table)

      # Caches pour les blocs répétables et découverte des tables
      @block_field_metadata_cache = {}
      @application_tables = nil
    end

    def sync_dossier(dossier)
      ensure_schema unless @schema_ensured

      # 1. Récupérer la row existante pour détecter les fichiers déjà présents
      existing_row = find_existing_row(@main_table, dossier.number)

      # 2. Extraire les données du dossier
      data_extractor = DataExtractor.new(@main_field_metadata, @options)
      extracted_data = data_extractor.extract_all(dossier, existing_row)

      # 3. Filtrer les champs read-only
      syncable_data = @main_field_filter.filter_syncable_fields(extracted_data[:main_table])

      # 4. Traiter les uploads de fichiers (téléchargement + upload multipart)
      syncable_data = process_file_uploads(syncable_data, @main_field_metadata)

      # 5. Upsert dans la table principale (avec field_metadata pour comparaison intelligente)
      # Passer existing_row (même si nil) pour éviter une recherche redondante
      upserter = RowUpserter.new(@main_table, @options, @main_field_metadata)
      main_row_id = upserter.upsert_row(dossier.number, syncable_data, existing_row: existing_row)

      # 7. Synchroniser les blocs répétables (auto-découverte)
      # Passer main_row_id pour éviter une recherche inutile
      sync_repetable_blocks(dossier.number, extracted_data[:repetable_blocks], main_row_id)

      Rails.logger.info "BaserowSync: Dossier #{dossier.number} synchronisé avec succès"
    end

    private

    def ensure_schema
      # TODO: Implémenter si nécessaire (SchemaBuilder)
      # Pour l'instant, on suppose que les tables existent déjà
      @schema_ensured = true
    end

    # Construit les métadonnées des champs à partir de table.fields
    def build_field_metadata(table)
      # Types de champs read-only (ne peuvent pas être mis à jour)
      readonly_types = %w[formula lookup rollup count created_on last_modified].freeze

      # Construire les métadonnées à partir de table.fields
      table.fields.transform_values do |field_data|
        {
          'id' => field_data[:id],
          'type' => field_data[:type],
          'primary' => field_data[:primary],
          'readonly' => readonly_types.include?(field_data[:type])
        }
      end
    end

    # Traite les uploads de fichiers en deux étapes :
    # 1. Télécharge les fichiers depuis Mes-Démarches (URLs S3)
    # 2. Uploade vers Baserow via multipart/form-data
    # Nécessaire car Baserow (advocate) bloque les adresses locales et les proxies
    # rubocop:disable Metrics/MethodLength
    def process_file_uploads(data, field_metadata)
      file_uploader = Baserow::FileUploader.new(@baserow_config['token_config'])

      data.each do |field_name, value|
        # Identifier les champs de type file
        next unless field_metadata[field_name]&.dig('type') == 'file'
        next if value.blank? || !value.is_a?(Array)

        # Traiter chaque fichier : uploader les nouveaux, conserver les existants
        processed_files = value.filter_map do |file_data|
          next unless file_data.is_a?(Hash)

          # Cas 1 : Fichier existant (avec hash Baserow) → conserver tel quel
          if file_data['name'] && !file_data[:url]
            file_data
          # Cas 2 : Nouveau fichier (avec URL) → télécharger + uploader
          elsif file_data[:url]
            visible_name = file_data[:visible_name] || 'fichier'
            result = file_uploader.download_and_upload(file_data[:url], visible_name)

            # Si l'upload échoue, skip ce fichier
            unless result
              Rails.logger.warn "BaserowSync: Échec upload fichier #{visible_name} pour champ #{field_name}"
              next
            end

            result
          end
        end

        # Mettre à jour le champ avec tous les fichiers (existants + nouveaux uploadés)
        # Si aucun fichier, retirer le champ pour ne pas envoyer un array vide
        if processed_files.empty?
          data.delete(field_name)
        else
          data[field_name] = processed_files
        end
      end

      data
    rescue StandardError => e
      Rails.logger.error "BaserowSync: Erreur traitement uploads fichiers: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise # Re-lever l'exception pour que le framework puisse gérer l'erreur
    end
    # rubocop:enable Metrics/MethodLength

    # Charge les métadonnées des champs d'une table de bloc répétable (avec cache)
    # Retourne un hash { nom_champ => { type: ..., ... } }
    def load_block_field_metadata(table_id)
      # Utiliser le cache si disponible
      return @block_field_metadata_cache[table_id] if @block_field_metadata_cache.key?(table_id)

      # Sinon, charger et mettre en cache
      field_filter = FieldFilter.new(table_id, @baserow_config['token_config'])
      @block_field_metadata_cache[table_id] = field_filter.load_baserow_fields
    rescue StandardError => e
      Rails.logger.error "BaserowSync: Erreur chargement métadonnées bloc #{table_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise # Re-lever pour que l'erreur soit gérée au niveau supérieur
    end

    def discover_application_tables
      return @application_tables if @application_tables

      # 1. Récupérer l'application_id depuis la table principale
      # StructureClient génère automatiquement un JWT via AuthService
      structure_client = Baserow::StructureClient.new
      main_table_info = structure_client.get_table(@baserow_config['table_id'])
      application_id = main_table_info['database_id']

      # 2. Lister toutes les tables de l'application
      tables = structure_client.list_tables(application_id)

      # 3. Créer un mapping nom → table_id
      @application_tables = tables.each_with_object({}) do |table, hash|
        hash[table['name']] = table['id']
      end

      Rails.logger.debug "BaserowSync: Tables découvertes dans l'application #{application_id}: #{@application_tables.keys.join(', ')}"

      @application_tables
    rescue StandardError => e
      Rails.logger.error "BaserowSync: Erreur découverte tables: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise # Re-lever pour que l'erreur soit gérée au niveau supérieur
    end

    def sync_repetable_blocks(dossier_number, blocks_data, main_row_id)
      return if blocks_data.blank?

      # Découvrir les tables de l'application
      available_tables = discover_application_tables

      blocks_data.each do |block_name, rows|
        # Chercher si une table avec ce nom existe dans Baserow
        table_id = available_tables[block_name]

        unless table_id
          Rails.logger.debug "BaserowSync: Table '#{block_name}' non trouvée dans Baserow, skip du bloc répétable"
          next
        end

        Rails.logger.info "BaserowSync: Synchronisation bloc répétable '#{block_name}' vers table #{table_id}"
        sync_block_rows(dossier_number, table_id, rows, main_row_id)
      end
    end

    def sync_block_rows(dossier_number, table_id, rows, main_row_id)
      # 1. Vérifier que l'ID de la row principale est disponible
      unless main_row_id
        Rails.logger.warn "BaserowSync: Row principale pour dossier #{dossier_number} introuvable, skip du bloc répétable (table #{table_id})"
        return
      end

      # 2. Récupérer les rows du bloc liées à ce dossier par ID
      block_table = get_table(table_id)
      existing_rows = block_table.find_by_link_row_id('Dossier', main_row_id)

      # 3. Charger les métadonnées des champs du bloc pour identifier les fichiers
      block_field_metadata = load_block_field_metadata(table_id)

      # 4. Synchroniser chaque row
      rows.each do |row_data|
        upsert_block_row(row_data, main_row_id, existing_rows, block_table, block_field_metadata, dossier_number)
      end

      # Supprimer les rows orphelines (par défaut: true, Baserow = miroir exact de Mes-Démarches)
      supprimer_orphelins = @options.key?('supprimer_orphelins') ? @options['supprimer_orphelins'] : true
      delete_orphan_rows(block_table, existing_rows, rows, dossier_number) if supprimer_orphelins
    rescue StandardError => e
      Rails.logger.error "BaserowSync: Erreur synchro bloc répétable (table #{table_id}): #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise unless @options['continuer_si_erreur']
    end

    # rubocop:disable Metrics/ParameterLists
    def upsert_block_row(row_data, main_row_id, existing_rows, block_table, block_field_metadata, dossier_number)
      # rubocop:enable Metrics/ParameterLists
      ligne = row_data['Ligne'].to_s
      existing = existing_rows.find { |r| r['Ligne'] == ligne }

      # IMPORTANT: Corriger le format du champ Dossier pour link_row
      # DataExtractor envoie le numéro (string), mais Baserow attend un array d'IDs
      row_data['Dossier'] = [main_row_id]

      # Traiter les uploads de fichiers dans le bloc
      row_data = process_file_uploads(row_data, block_field_metadata)

      if existing
        # Filtrer pour n'envoyer que les champs modifiés
        upserter = RowUpserter.new(block_table, @options, block_field_metadata)
        changed_data = upserter.send(:filter_changed_fields, row_data, existing)

        if changed_data.empty?
          Rails.logger.debug "BaserowSync: Bloc ligne #{ligne} inchangée (dossier #{dossier_number})"
        else
          block_table.update_row(existing['id'], changed_data)
          Rails.logger.debug "BaserowSync: Bloc ligne #{ligne} mise à jour (#{changed_data.keys.length} champ(s), dossier #{dossier_number})"
        end
      else
        # Nouvelle row
        block_table.create_row(row_data)
        Rails.logger.debug "BaserowSync: Bloc ligne #{ligne} créée (dossier #{dossier_number})"
      end
    end

    def delete_orphan_rows(block_table, existing_rows, current_rows, dossier_number)
      # Créer un Set des numéros de ligne actuels pour une recherche rapide
      current_lignes = current_rows.to_set { |r| r['Ligne'].to_s }

      existing_rows.each do |row|
        # Si la ligne n'existe plus dans le dossier, la supprimer
        next if current_lignes.include?(row['Ligne'])

        block_table.delete_row(row['id'])
        Rails.logger.info "BaserowSync: Row orpheline supprimée: dossier #{dossier_number}, ligne #{row['Ligne']} (Bloc: #{row['Bloc']})"
      end
    end

    def find_existing_row(table, dossier_number)
      # Utiliser find_by_normalized pour obtenir les noms de champs lisibles (user_field_names=true)
      # Nécessaire pour détecter les fichiers existants dans normalize_files
      results = table.find_by_normalized('Dossier', dossier_number.to_s)
      results.first
    rescue StandardError => e
      Rails.logger.error "BaserowSync: Erreur recherche row existante: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise # Re-lever pour que l'erreur soit visible et gérée
    end

    def get_table(table_id)
      Baserow::Config.table(
        table_id,
        @baserow_config['token_config']
      )
    end
  end
end
