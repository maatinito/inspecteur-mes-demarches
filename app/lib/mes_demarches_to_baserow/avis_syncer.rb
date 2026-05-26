# frozen_string_literal: true

module MesDemarchesToBaserow
  # Orchestre la synchronisation des avis d'un dossier vers la table Baserow "Avis".
  #
  # Responsabilités:
  # - Découverte de la table "Avis" (skip silencieux si absente)
  # - Validation de la structure minimale (primary "Avis" + link_row "Dossier")
  # - Upsert par ID GraphQL de l'avis (clé stable)
  # - Suppression des avis orphelins (rows Baserow dont l'ID n'est plus présent côté MD)
  class AvisSyncer
    AVIS_TABLE_NAME = 'Avis'
    PRIMARY_FIELD = 'Avis'
    LINK_FIELD = 'Dossier'

    def initialize(application_tables:, main_table_id:, baserow_config:, options:,
                   field_metadata_loader:, structure_client: nil)
      @application_tables = application_tables || {}
      @main_table_id = main_table_id
      @baserow_config = baserow_config
      @options = options || {}
      @field_metadata_loader = field_metadata_loader
      @structure_client = structure_client || Baserow::StructureClient.new
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def sync(dossier, main_row_id, file_uploader_proc)
      table_id = @application_tables[AVIS_TABLE_NAME]
      unless table_id
        Rails.logger.debug "BaserowSync.avis: table '#{AVIS_TABLE_NAME}' absente, skip"
        return
      end

      return unless valid_structure?(table_id)

      avis_list = MesDemarches::AvisFetcher.fetch(dossier.number)
      Rails.logger.info "BaserowSync.avis: #{avis_list.length} avis à synchroniser pour dossier #{dossier.number}"

      avis_table = get_table(table_id)
      existing_rows = avis_table.find_by_link_row_id(LINK_FIELD, main_row_id)
      field_metadata = @field_metadata_loader.call(table_id)
      extractor = DataExtractor.new(field_metadata, @options)

      current_ids = []
      avis_list.each do |avis|
        current_ids << avis.id.to_s
        existing_row = existing_rows.find { |r| r[PRIMARY_FIELD].to_s == avis.id.to_s }
        existing_attachments = existing_row ? Array(existing_row['Pièces jointes']) : []

        row_data = extractor.extract_avis_row(avis, main_row_id, existing_attachments)
        # DataExtractor#extract_avis_row produit 'Dossier' => main_row_id.to_s (string),
        # contrat partagé avec les blocs répétables (cf. sync_coordinator.rb:387-389).
        # AvisSyncer le convertit en [main_row_id] (format link_row Baserow) ici.
        row_data[LINK_FIELD] = [main_row_id]

        file_uploader_proc.call(row_data, field_metadata)

        if existing_row
          upserter = RowUpserter.new(avis_table, @options, field_metadata)
          changed = upserter.send(:filter_changed_fields, row_data, existing_row)
          if changed.empty?
            Rails.logger.debug "BaserowSync.avis: avis #{avis.id} inchangé"
          else
            avis_table.update_row(existing_row['id'], changed)
            Rails.logger.info "BaserowSync.avis: avis #{avis.id} mis à jour (#{changed.keys.length} champ(s))"
          end
        else
          avis_table.create_row(row_data)
          Rails.logger.info "BaserowSync.avis: avis #{avis.id} créé"
        end
      end

      delete_orphans(avis_table, existing_rows, current_ids, dossier.number) if supprimer_orphelins?
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    # rubocop:disable Metrics/MethodLength
    def valid_structure?(table_id)
      primary = @structure_client.get_primary_field(table_id)
      unless primary && primary['name'] == PRIMARY_FIELD
        Rails.logger.warn "BaserowSync.avis: structure invalide (table #{table_id}) — primary attendu " \
                          "'#{PRIMARY_FIELD}', trouvé '#{primary&.dig('name')}'"
        return false
      end

      link = @structure_client.get_field_by_name(table_id, LINK_FIELD)
      unless link && link['type'] == 'link_row'
        Rails.logger.warn "BaserowSync.avis: structure invalide (table #{table_id}) — champ " \
                          "'#{LINK_FIELD}' link_row manquant ou type incorrect"
        return false
      end

      unless link['link_row_table_id'].to_s == @main_table_id.to_s
        Rails.logger.warn "BaserowSync.avis: structure invalide (table #{table_id}) — '#{LINK_FIELD}' " \
                          "pointe vers table #{link['link_row_table_id']} au lieu de #{@main_table_id}"
        return false
      end

      if link['link_row_multiple_relationships'] == true
        Rails.logger.warn "BaserowSync.avis: structure invalide (table #{table_id}) — '#{LINK_FIELD}' " \
                          'autorise plusieurs liens (link_row_multiple_relationships=true)'
        return false
      end

      true
    rescue Baserow::APIError => e
      Rails.logger.error "BaserowSync.avis: erreur validation structure: #{e.message}"
      false
    end
    # rubocop:enable Metrics/MethodLength

    def delete_orphans(avis_table, existing_rows, current_ids, dossier_number)
      orphans = existing_rows.reject { |r| current_ids.include?(r[PRIMARY_FIELD].to_s) }
      return if orphans.empty?

      orphans.each do |row|
        avis_table.delete_row(row['id'])
        Rails.logger.info "BaserowSync.avis: avis orphelin supprimé (dossier #{dossier_number}, avis #{row[PRIMARY_FIELD]})"
      end
    end

    def supprimer_orphelins?
      @options.key?('supprimer_orphelins') ? @options['supprimer_orphelins'] : true
    end

    def get_table(table_id)
      Baserow::Config.table(table_id, @baserow_config['token_config'])
    end
  end
end
