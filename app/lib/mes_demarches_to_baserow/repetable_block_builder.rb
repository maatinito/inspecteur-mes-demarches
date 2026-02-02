# frozen_string_literal: true

module MesDemarchesToBaserow
  class RepetableBlockBuilder
    class BlockError < StandardError; end

    attr_reader :demarche_number, :main_table_id, :application_id, :report

    def initialize(demarche_number, main_table_id, application_id)
      @demarche_number = demarche_number
      @main_table_id = main_table_id
      @application_id = application_id
      @structure_client = Baserow::StructureClient.new
      @type_mapper = TypeMapper.new
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
            fields_count: block.champs.length,
            fields: block.champs.map { |champ| format_field_info(champ) }
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
      # Lister les tables de l'application
      application = @structure_client.get_application(@application_id)
      tables = application['tables'] || []

      tables.find { |table| table['name'] == table_name }
    end

    def create_repetable_table(table_name, block)
      # 1. Créer la table Baserow
      table_data = {
        name: table_name,
        data: [
          [{ value: 'Dossier' }] # Première colonne = Dossier (jointure)
        ]
      }

      new_table = @structure_client.create_table(@application_id, table_data)
      table_id = new_table['id']

      @report[:tables_created] << {
        name: table_name,
        id: table_id,
        block_label: block.label
      }

      # 2. Créer les colonnes pour chaque champ du bloc
      create_block_fields(table_id, block)

      # 3. Créer le lien dans la table principale
      create_link_field(table_name, table_id)
    rescue Baserow::ApiError => e
      @report[:errors] << "Erreur création table #{table_name}: #{e.message}"
    end

    def update_repetable_table(existing_table, block)
      table_id = existing_table['id']
      table_name = existing_table['name']

      @report[:tables_updated] << {
        name: table_name,
        id: table_id,
        block_label: block.label
      }

      # Ajouter les colonnes manquantes
      create_block_fields(table_id, block)

      # Vérifier/créer le lien dans la table principale si absent
      link_field_name = table_name
      create_link_field(table_name, table_id) unless @structure_client.field_exists?(@main_table_id, link_field_name)
    rescue Baserow::ApiError => e
      @report[:errors] << "Erreur mise à jour table #{table_name}: #{e.message}"
    end

    def create_block_fields(table_id, block)
      # Pour chaque champ du bloc, créer une colonne
      block.champs.each do |champ|
        field_type = champ.__typename

        # Ignorer les types non supportés
        next if TypeMapper.should_ignore_type?(field_type)
        next unless TypeMapper.supported_type?(field_type)

        field_name = @type_mapper.generate_field_name(champ.label)

        # Skip si existe déjà
        next if @structure_client.field_exists?(table_id, field_name)

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
      rescue Baserow::ApiError => e
        @report[:errors] << "Erreur création champ #{field_name}: #{e.message}"
      end
    end

    def create_link_field(target_table_name, target_table_id)
      # Créer un champ "Link to table" dans la table principale
      link_field_name = target_table_name

      field_data = {
        type: 'link_row',
        name: link_field_name,
        link_row_table_id: target_table_id
      }

      @structure_client.create_field(@main_table_id, field_data)

      @report[:link_fields_created] << {
        name: link_field_name,
        target_table: target_table_name,
        target_table_id: target_table_id
      }
    rescue Baserow::ApiError => e
      @report[:errors] << "Erreur création lien #{link_field_name}: #{e.message}"
    end
  end
end
