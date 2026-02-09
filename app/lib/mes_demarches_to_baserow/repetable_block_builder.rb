# frozen_string_literal: true

module MesDemarchesToBaserow
  class RepetableBlockBuilder
    class BlockError < StandardError; end

    attr_reader :demarche_number, :main_table_id, :application_id, :workspace_id, :report

    def initialize(demarche_number, main_table_id, application_id, workspace_id)
      @demarche_number = demarche_number
      @main_table_id = main_table_id
      @application_id = application_id
      @workspace_id = workspace_id
      @structure_client = Baserow::StructureClient.new
      @type_mapper = TypeMapper.new
      @created_tables = {} # Cache local des tables créées pendant cette exécution
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
            suggested_table_name: block.label,
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
      # Chercher dans champ_descriptors ET annotation_descriptors
      all_descriptors = (revision.champ_descriptors || []) + (revision.annotation_descriptors || [])

      all_descriptors.select do |descriptor|
        descriptor.__typename == 'RepetitionChampDescriptor'
      end
    end

    def format_field_info(champ)
      {
        label: champ.label,
        type: champ.__typename,
        supported: TypeMapper.supported_type?(champ.__typename)
      }
    end

    def validate_main_table!
      # Vérifier que la table principale existe
      table = @structure_client.get_table(@main_table_id)
      raise BlockError, "Table principale #{@main_table_id} introuvable" unless table

      # Vérifier que la table a bien un champ "Dossier"
      return if @structure_client.field_exists?(@main_table_id, 'Dossier')

      raise BlockError, 'La table principale doit avoir un champ "Dossier" (numéro de dossier)'
    end

    def create_or_update_repetable_table(block_config)
      champ_id = block_config['champ_id']
      table_name = block_config['table_name']

      # Récupérer le bloc depuis la démarche
      demarche = fetch_demarche
      revision = demarche.draft_revision || demarche.published_revision
      repetable_blocks = extract_repetable_blocks(revision)

      block = repetable_blocks.find { |b| b.id == champ_id }
      raise BlockError, "Bloc #{champ_id} introuvable" unless block

      # Chercher si la table existe déjà
      existing_table = find_table_by_name(table_name)

      if existing_table
        update_repetable_table(existing_table, block)
      else
        create_repetable_table(table_name, block)
      end
    end

    def find_table_by_name(table_name)
      # Vérifier d'abord dans le cache local (tables créées pendant cette exécution)
      return @created_tables[table_name] if @created_tables.key?(table_name)

      # Sinon, chercher dans les tables existantes
      applications = @structure_client.list_applications(@workspace_id)
      application = applications.find { |app| app['id'].to_s == @application_id.to_s }

      return nil unless application

      # Les tables sont incluses dans la réponse de l'application
      tables = application['tables'] || []
      tables.find { |table| table['name'] == table_name }
    end

    def create_repetable_table(table_name, block)
      table_id = create_table_with_ligne_field(table_name, block)
      ensure_table_structure(table_id, table_name)
      create_block_fields(table_id, block)
    rescue StandardError => e
      error_msg = "Erreur création table #{table_name}: #{e.message}"
      Rails.logger.error "RepetableBlockBuilder: #{error_msg}"
      Rails.logger.error e.backtrace.join("\n")
      @report[:errors] << error_msg
    end

    def update_repetable_table(existing_table, block)
      table_id = existing_table['id']
      table_name = existing_table['name']

      @report[:tables_updated] << {
        name: table_name,
        id: table_id,
        block_label: block.label
      }

      ensure_table_structure(table_id, table_name)
      create_block_fields(table_id, block)
    rescue StandardError => e
      error_msg = "Erreur mise à jour table #{table_name}: #{e.message}"
      Rails.logger.error "RepetableBlockBuilder: #{error_msg}"
      Rails.logger.error e.backtrace.join("\n")
      @report[:errors] << error_msg
    end

    def create_block_fields(table_id, block)
      # Récupérer tous les champs existants UNE SEULE FOIS pour éviter les multiples appels API
      existing_fields = @structure_client.get_table_fields(table_id)
      existing_field_names = Set.new(existing_fields.map { |f| f['name']&.downcase })

      # Pour chaque champ du bloc, créer une colonne
      block.champ_descriptors.each do |champ|
        field_type = champ.__typename

        # Ignorer les types non supportés
        next if TypeMapper.should_ignore_type?(field_type)
        next unless TypeMapper.supported_type?(field_type)

        field_name = @type_mapper.generate_field_name(champ.label)

        # Skip si existe déjà
        next if existing_field_names.include?(field_name.downcase)

        # Créer le champ
        mapping = @type_mapper.map_field_type(field_type, champ.to_h)

        field_data = {
          type: mapping[:type],
          name: field_name
        }
        field_data.merge!(mapping[:config]) if mapping[:config].any?

        @structure_client.create_field(table_id, field_data)

        @report[:fields_created] << {
          table: table_id,
          name: field_name,
          type: mapping[:type]
        }
      rescue TypeMapper::UnsupportedTypeError
        # Skip silencieux pour les types non supportés
      rescue Baserow::APIError => e
        @report[:errors] << "Erreur création champ #{field_name}: #{e.message}"
      end
    end

    def create_link_to_main_table(block_table_id)
      # Créer un champ "Link to table" DANS la table du bloc qui pointe vers la table principale
      # Cela créera automatiquement le champ inverse dans la table principale
      field_data = {
        type: 'link_row',
        name: 'Dossier',
        link_row_table_id: @main_table_id,
        has_related_field: true,
        link_row_multiple_relationships: false # Un bloc ne peut pointer que vers UN seul dossier
      }

      link_field = @structure_client.create_field(block_table_id, field_data)

      @report[:link_fields_created] << {
        name: 'Dossier',
        from_table_id: block_table_id,
        to_table_id: @main_table_id,
        link_field_id: link_field['id']
      }
    rescue Baserow::APIError => e
      @report[:errors] << "Erreur création lien Dossier: #{e.message}"
    end

    # Garantit que la table a la structure requise pour un bloc répétable :
    # - Champ "Ligne" (number)
    # - Champ "Dossier" (link_row vers table principale, limité à un seul lien)
    # - Champ primaire "Bloc" (formula)
    def ensure_table_structure(table_id, table_name)
      # 1. Vérifier/créer le champ "Ligne" s'il n'existe pas
      unless @structure_client.field_exists?(table_id, 'Ligne')
        Rails.logger.info "RepetableBlockBuilder: Création du champ 'Ligne' pour la table #{table_name}"
        @structure_client.create_field(table_id, {
                                         type: 'number',
                                         name: 'Ligne',
                                         number_decimal_places: 0
                                       })
      end

      # 2. Vérifier/créer le lien "Dossier" s'il n'existe pas
      dossier_field = @structure_client.get_field_by_name(table_id, 'Dossier')
      if dossier_field
        # Le champ existe, vérifier qu'il est configuré pour un seul lien
        ensure_single_link_dossier(dossier_field, table_name)
      else
        # Le champ n'existe pas, le créer
        Rails.logger.info "RepetableBlockBuilder: Création du lien 'Dossier' pour la table #{table_name}"
        create_link_to_main_table(table_id)
      end

      # 3. Vérifier/corriger le champ primaire "Bloc" en formula
      ensure_bloc_field_is_formula(table_id, table_name)
    rescue Baserow::APIError => e
      error_msg = "Erreur lors de la vérification de la structure de la table #{table_name}: #{e.message}"
      Rails.logger.error "RepetableBlockBuilder: #{error_msg}"
      @report[:errors] << error_msg
    end

    def ensure_single_link_dossier(dossier_field, table_name)
      # Vérifier que le champ "Dossier" n'autorise qu'un seul lien
      if dossier_field['link_row_multiple_relationships'] == false
        Rails.logger.debug "RepetableBlockBuilder: Champ 'Dossier' déjà configuré pour un seul lien dans la table #{table_name}"
        return
      end

      # Si multiple relationships est activé, le désactiver
      Rails.logger.info "RepetableBlockBuilder: Désactivation des liens multiples pour le champ 'Dossier' dans la table #{table_name}"

      @structure_client.update_field(dossier_field['id'], {
                                       link_row_multiple_relationships: false
                                     })

      Rails.logger.info "RepetableBlockBuilder: Champ 'Dossier' modifié avec succès (limité à un seul lien)"
    rescue Baserow::APIError => e
      error_msg = "Impossible de modifier le champ 'Dossier' pour limiter à un seul lien dans la table #{table_name}: #{e.message}"
      Rails.logger.error "RepetableBlockBuilder: #{error_msg}"
      @report[:errors] << error_msg
      # Ne pas lever l'erreur, continuer
    end

    def ensure_bloc_field_is_formula(table_id, table_name)
      # Récupérer le champ primaire (devrait être "Bloc")
      primary_field = @structure_client.get_primary_field(table_id)

      # Vérifier si c'est déjà une formula
      if primary_field['type'] == 'formula'
        Rails.logger.debug "RepetableBlockBuilder: Champ primaire '#{primary_field['name']}' est déjà une formula pour la table #{table_name}"
        return
      end

      # Si ce n'est pas une formula, la convertir
      Rails.logger.info "RepetableBlockBuilder: Conversion du champ primaire '#{primary_field['name']}' en formula pour la table #{table_name}"

      @structure_client.update_field(primary_field['id'], {
                                       type: 'formula',
                                       formula: "join(totext(field('Dossier')),'')+'-'+totext(field('Ligne'))"
                                     })

      Rails.logger.info 'RepetableBlockBuilder: Champ primaire modifié avec succès en formula'
    rescue Baserow::APIError => e
      error_msg = "Impossible de modifier le champ primaire '#{primary_field&.dig('name') || 'Bloc'}' en formula pour la table #{table_name}: #{e.message}"
      Rails.logger.error "RepetableBlockBuilder: #{error_msg}"
      @report[:errors] << error_msg
      # Ne pas lever l'erreur, continuer avec le champ actuel
    end

    def create_table_with_ligne_field(table_name, block)
      # 1. Créer table avec "Bloc" (text temporaire) comme champ primaire
      table_data = {
        name: table_name,
        data: [['Bloc']],
        first_row_header: true
      }

      new_table = @structure_client.create_table(@application_id, table_data)
      table_id = new_table['id']

      # 2. Créer champ "Ligne" (number)
      @structure_client.create_field(table_id, {
                                       type: 'number',
                                       name: 'Ligne',
                                       number_decimal_places: 0
                                     })

      # NOTE: Le lien "Dossier" et la conversion en formula seront faits par ensure_table_structure

      @created_tables[table_name] = new_table

      @report[:tables_created] << {
        name: table_name,
        id: table_id,
        block_label: block.label
      }

      table_id
    end
  end
end
