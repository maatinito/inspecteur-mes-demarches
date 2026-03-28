# frozen_string_literal: true

module MesDemarchesToBaserow
  # Coordonne la synchronisation d'une démarche vers Baserow
  #
  # Responsabilités:
  # - Initialiser/mettre à jour le schéma Baserow (première fois)
  # - Coordonner l'extraction, le filtrage et l'upsert des données
  # - Gérer les blocs répétables (tables liées)
  class SyncCoordinator
    # Mapping couleurs Mes-Démarches → Baserow
    MES_DEMARCHES_TO_BASEROW_COLORS = {
      'green' => 'green', 'blue' => 'blue', 'red' => 'red',
      'orange' => 'orange', 'yellow' => 'yellow', 'purple' => 'purple',
      'pink' => 'pink', 'grey' => 'light-gray', 'gray' => 'light-gray'
    }.freeze

    DEFAULT_OPTION_COLORS = %w[blue green red yellow orange purple pink light-blue light-green light-red].freeze

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

      # Caches pour les blocs répétables, découverte des tables et link_row
      @block_field_metadata_cache = {}
      @application_tables = nil
      @link_row_cache = {} # { table_id => { primary_value => row_id } }
      @select_options_cache = {} # { field_id => Set[known_values] }
      @failed_uploads = []
    end

    def sync_dossier(dossier)
      ensure_schema unless @schema_ensured
      @failed_uploads = []

      # 1. Récupérer la row existante pour détecter les fichiers déjà présents
      existing_row = find_existing_row(@main_table, dossier.number)

      # 2. Extraire les données du dossier
      data_extractor = DataExtractor.new(@main_field_metadata, @options)
      extracted_data = data_extractor.extract_all(dossier, existing_row)

      # 3. Filtrer les champs read-only
      syncable_data = @main_field_filter.filter_syncable_fields(extracted_data[:main_table])

      # 4. Traiter les uploads de fichiers (téléchargement + upload multipart)
      process_file_uploads(syncable_data, @main_field_metadata)

      # 4b. Résoudre les champs link_row (lookup/création dans table cible)
      resolve_link_rows(syncable_data)

      # 4c. S'assurer que les options select existent dans Baserow
      @pending_select_colors = data_extractor.label_colors || {}
      ensure_select_options(syncable_data)

      # 5. Upsert dans la table principale (avec field_metadata pour comparaison intelligente)
      # Passer existing_row (même si nil) pour éviter une recherche redondante
      upserter = RowUpserter.new(@main_table, @options, @main_field_metadata)
      main_row_id = upserter.upsert_row(dossier.number, syncable_data, existing_row: existing_row)

      # 7. Synchroniser les blocs répétables (auto-découverte)
      # Passer main_row_id pour éviter une recherche inutile
      sync_repetable_blocks(dossier.number, extracted_data[:repetable_blocks], main_row_id)

      # 8. Si des fichiers ont échoué, lever une exception APRÈS l'upsert
      # pour que le framework marque le dossier en échec et le retente.
      # Au retry, les fichiers déjà uploadés seront détectés comme existants.
      raise "Upload fichiers échoué: #{@failed_uploads.join(', ')}" if @failed_uploads.present?

      Rails.logger.info "BaserowSync: Dossier #{dossier.number} synchronisé avec succès"
    end

    private

    def ensure_schema
      # TODO: Implémenter si nécessaire (SchemaBuilder)
      # Pour l'instant, on suppose que les tables existent déjà
      @schema_ensured = true
    end

    # Construit les métadonnées des champs depuis l'API Baserow (config complète)
    # Nécessaire pour les link_row (link_row_table_id, link_row_table_primary_field)
    def build_field_metadata(table)
      readonly_types = %w[formula lookup rollup count created_on last_modified].freeze

      client = Baserow::Config.client(@baserow_config['token_config'])
      fields = client.list_fields(table.table_id)

      fields.each_with_object({}) do |field, hash|
        meta = {
          'id' => field['id'],
          'type' => field['type'],
          'primary' => field['primary'],
          'readonly' => readonly_types.include?(field['type'])
        }

        # Conserver la config link_row pour resolve_link_rows
        if field['type'] == 'link_row'
          meta['link_row_table_id'] = field['link_row_table_id']
          meta['link_row_table_primary_field'] = field['link_row_table_primary_field']
        end

        hash[field['name']] = meta
      end
    end

    # Traite les uploads de fichiers en deux étapes :
    # 1. Télécharge les fichiers depuis Mes-Démarches (URLs S3)
    # 2. Uploade vers Baserow via multipart/form-data
    # Nécessaire car Baserow (advocate) bloque les adresses locales et les proxies
    # rubocop:disable Metrics/MethodLength
    def process_file_uploads(data, field_metadata)
      file_uploader = Baserow::FileUploader.new(@baserow_config['token_config'])
      failed_uploads = []

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

            unless result
              failed_uploads << "#{field_name}/#{visible_name}"
              next
            end

            result
          end
        end

        # Mettre à jour le champ avec les fichiers réussis (existants + nouveaux uploadés)
        if processed_files.empty?
          data.delete(field_name)
        else
          data[field_name] = processed_files
        end
      end

      # Mémoriser les échecs pour lever après l'upsert
      @failed_uploads = failed_uploads
    end
    # rubocop:enable Metrics/MethodLength

    # Résout les champs link_row : cherche (ou crée) la row dans la table cible
    # et remplace la valeur texte par un array d'IDs Baserow
    def resolve_link_rows(data)
      data.each do |field_name, value|
        next if value.blank?

        meta = @main_field_metadata[field_name]
        next unless meta&.dig('type') == 'link_row'

        target_table_id = meta['link_row_table_id']
        primary_field_name = meta.dig('link_row_table_primary_field', 'name')
        primary_field_type = meta.dig('link_row_table_primary_field', 'type')
        next unless target_table_id && primary_field_name

        # Normaliser la valeur selon le type de la colonne primaire cible
        # Ex: DossierLink "599761 -" → 599761 pour une colonne number
        normalized = normalize_link_row_value(value.to_s, primary_field_type)
        next if normalized.blank?

        row_id = find_or_create_link_row(target_table_id, primary_field_name, normalized)
        if row_id
          data[field_name] = [row_id]
        else
          data.delete(field_name)
        end
      end
    end

    # Normalise la valeur selon le type attendu par la colonne primaire cible
    def normalize_link_row_value(value, primary_field_type)
      case primary_field_type
      when 'number'
        # Extraire le premier nombre entier (ex: "599761 -" → "599761")
        match = value.match(/\A\s*(\d+)/)
        match ? match[1].to_i : nil
      else
        value
      end
    end

    # Cherche une row par sa clé primaire dans la table cible, la crée si absente
    # Utilise un cache pour éviter les appels répétés
    def find_or_create_link_row(table_id, primary_field, value)
      @link_row_cache[table_id] ||= {}
      return @link_row_cache[table_id][value] if @link_row_cache[table_id].key?(value)

      table = get_table(table_id)
      results = table.find_by_normalized(primary_field, value)

      row_id = if results.any?
                 results.first['id']
               else
                 Rails.logger.info "BaserowSync: Création entrée '#{value}' dans table #{table_id}"
                 new_row = table.create_row({ primary_field => value })
                 new_row['id']
               end

      @link_row_cache[table_id][value] = row_id
    rescue Baserow::ApiError => e
      Rails.logger.error "BaserowSync: Erreur résolution link_row '#{value}' (table #{table_id}): #{e.message}"
      nil
    end

    # Vérifie que les options select/multiple_select existent dans Baserow
    # Crée les options manquantes à la volée via StructureClient
    # En cas d'échec, les valeurs sont conservées dans data (l'upsert tentera quand même)
    def ensure_select_options(data)
      data.each do |field_name, value|
        next if value.nil?

        meta = @main_field_metadata[field_name]
        next unless meta && %w[single_select multiple_select].include?(meta['type'])

        field_id = meta['id']
        values = meta['type'] == 'multiple_select' ? Array(value) : [value]
        values = values.compact.map(&:to_s).reject(&:blank?)
        next if values.empty?

        ensure_field_options(field_id, values)
      end
    end

    # S'assure que les valeurs existent comme options du champ select
    def ensure_field_options(field_id, values)
      # Charger le cache des options existantes au premier appel
      unless @select_options_cache.key?(field_id)
        structure_client = Baserow::StructureClient.new
        field_data = structure_client.get_field(field_id)
        existing = (field_data['select_options'] || []).map { |opt| opt['value'] }
        @select_options_cache[field_id] = Set.new(existing)
      end

      known = @select_options_cache[field_id]
      missing = values.reject { |v| known.include?(v) }
      return if missing.empty?

      # Ajouter les options manquantes avec couleur
      structure_client = Baserow::StructureClient.new
      field_data = structure_client.get_field(field_id)
      current_options = field_data['select_options'] || []

      # Nettoyer les options existantes (ne garder que id/value/color) pour éviter les champs parasites
      clean_options = current_options.map { |opt| opt.slice('id', 'value', 'color') }
      color_offset = clean_options.length
      new_entries = missing.each_with_index.map do |v, i|
        { 'value' => v, 'color' => baserow_color_for(v, color_offset + i) }
      end

      structure_client.update_field(field_id, { select_options: clean_options + new_entries })
      missing.each { |v| known.add(v) }

      Rails.logger.info "BaserowSync: Options ajoutées au champ #{field_id}: #{missing.join(', ')}"
    rescue Baserow::APIError => e
      detail = e.respond_to?(:error_data) ? e.error_data : e.message
      Rails.logger.error "BaserowSync: Erreur ajout options select (champ #{field_id}): #{detail}"
    end

    # Détermine la couleur Baserow pour une nouvelle option select
    # Utilise la couleur du label Mes-Démarches si disponible, sinon round-robin
    def baserow_color_for(value, index)
      if @pending_select_colors&.key?(value)
        md_color = @pending_select_colors[value].to_s.downcase
        return MES_DEMARCHES_TO_BASEROW_COLORS[md_color] if MES_DEMARCHES_TO_BASEROW_COLORS.key?(md_color)
      end
      DEFAULT_OPTION_COLORS[index % DEFAULT_OPTION_COLORS.length]
    end

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
      @application_tables = tables.to_h do |table|
        [table['name'], table['id']]
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
      raise
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
