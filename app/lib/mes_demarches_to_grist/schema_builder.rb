# frozen_string_literal: true

module MesDemarchesToGrist
  class SchemaBuilder
    class SchemaError < StandardError; end

    attr_reader :demarche_number, :doc_id, :table_id, :options, :report

    def initialize(demarche_number, doc_id, table_id, options = {})
      @demarche_number = demarche_number
      @doc_id = doc_id
      @table_id = table_id
      @options = default_options.merge(options)
      @type_mapper = TypeMapper.new
      @client = Grist::Config.client
      @report = {
        fields_created: [],
        fields_updated: [],
        fields_skipped: [],
        fields_failed: [],
        errors: []
      }
    end

    def preview
      fields_to_create = collect_fields_to_create
      mark_existing_fields(fields_to_create)
      {
        total_fields: fields_to_create.length,
        existing_fields: fields_to_create.count { |f| f[:exists_in_grist] },
        new_fields: fields_to_create.count { |f| !f[:exists_in_grist] },
        supported_fields: fields_to_create.count { |f| f[:supported] },
        unsupported_fields: fields_to_create.count { |f| !f[:supported] },
        fields: fields_to_create
      }
    end

    def build!(selected_fields: nil)
      validate_demarche_access!

      fields_to_create = collect_fields_to_create.select { |f| f[:supported] }
      fields_to_create.select! { |f| selected_fields.include?(f[:field_name]) } if selected_fields.present?

      if fields_to_create.empty?
        @report[:warnings] ||= []
        @report[:warnings] << 'Aucun champ sélectionné pour la création'
        return @report
      end

      # Créer les colonnes en batch via l'API Grist
      create_columns_batch(fields_to_create)

      @report
    end

    private

    def default_options
      {
        include_fields: true,
        include_annotations: true,
        include_identity_info: false,
        collision_strategy: 'skip',
        field_prefix: nil,
        annotation_prefix: nil
      }
    end

    def validate_demarche_access!
      result = MesDemarches.query(MesDemarches::Queries::DemarcheRevision, variables: { demarche: @demarche_number })

      raise SchemaError, "Erreur lors de l'accès à la démarche #{@demarche_number}: #{result.errors.map(&:message).join(', ')}" if result.errors.any?

      demarche = result.data&.demarche
      raise SchemaError, "Démarche #{@demarche_number} introuvable ou accès non autorisé" if demarche.nil?

      demarche
    end

    def mark_existing_fields(fields)
      existing_columns = @client.list_columns(@doc_id, @table_id)
      existing_col_ids = Set.new((existing_columns['columns'] || []).map { |c| c['id'] })

      fields.each do |field_info|
        # Grist utilise l'ID de colonne (= nom) pour identifier les colonnes
        col_id = sanitize_column_id(field_info[:field_name])
        field_info[:exists_in_grist] = existing_col_ids.include?(col_id)
        field_info[:is_mandatory] = (field_info[:field_name] == 'Dossier')
        field_info[:grist_col_id] = col_id
      end
    rescue Grist::APIError
      fields.each do |field_info|
        field_info[:exists_in_grist] = false
        field_info[:is_mandatory] = (field_info[:field_name] == 'Dossier')
        field_info[:grist_col_id] = sanitize_column_id(field_info[:field_name])
      end
    end

    def collect_fields_to_create
      demarche = validate_demarche_access!
      revision = demarche.draft_revision || demarche.published_revision

      raise SchemaError, "Démarche #{@demarche_number} n'a ni révision en brouillon ni révision publiée disponible" unless revision

      fields = []
      fields.concat(identity_fields) if @options[:include_identity_info]
      fields.concat(process_field_descriptors(revision.champ_descriptors, 'champ')) if @options[:include_fields]
      fields.concat(process_field_descriptors(revision.annotation_descriptors, 'annotation')) if @options[:include_annotations]
      fields
    end

    def process_field_descriptors(descriptors, category)
      descriptors.filter_map { |descriptor| process_single_descriptor(descriptor, category) }
    end

    def process_single_descriptor(descriptor, category)
      field_type = descriptor.__typename
      return nil if TypeMapper.should_ignore_type?(field_type)

      build_field_info(descriptor, category, field_type)
    end

    def build_field_info(descriptor, category, field_type)
      supported = TypeMapper.supported_type?(field_type)
      prefix = determine_prefix(category)
      field_name = @type_mapper.generate_field_name(descriptor.label, prefix)

      field_info = base_field_info(descriptor, field_name, field_type, category, supported)
      add_grist_mapping(field_info, field_type, descriptor) if supported
      field_info
    end

    def determine_prefix(category)
      case category
      when 'champ' then @options[:field_prefix]
      when 'annotation' then @options[:annotation_prefix]
      end
    end

    def base_field_info(descriptor, field_name, field_type, category, supported)
      {
        original_label: descriptor.label,
        field_name: field_name,
        mes_demarches_type: field_type,
        category: category,
        supported: supported,
        required: descriptor.required || false,
        description: descriptor.description
      }
    end

    def add_grist_mapping(field_info, field_type, descriptor)
      mapping = @type_mapper.map_field_type(field_type, descriptor.to_h)
      field_info[:grist_type] = mapping[:type]
      field_info[:grist_config] = mapping[:config]
    rescue TypeMapper::UnsupportedTypeError => e
      field_info[:supported] = false
      field_info[:error] = e.message
    end

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def create_columns_batch(fields_to_create)
      # Récupérer les colonnes existantes
      existing_columns = @client.list_columns(@doc_id, @table_id)
      existing_col_ids = Set.new((existing_columns['columns'] || []).map { |c| c['id'] })

      columns_to_add = []

      fields_to_create.each do |field_info|
        col_id = sanitize_column_id(field_info[:field_name])

        if existing_col_ids.include?(col_id)
          case @options[:collision_strategy]
          when 'skip'
            @report[:fields_skipped] << { name: field_info[:field_name], reason: 'field_exists' }
            next
          when 'error'
            raise SchemaError, "La colonne '#{field_info[:field_name]}' existe déjà dans la table"
          when 'rename'
            col_id = find_available_col_id(col_id, existing_col_ids)
          end
        end

        col_data = {
          id: col_id,
          fields: { label: field_info[:field_name], type: field_info[:grist_type], isFormula: false }
        }

        # Ajouter widgetOptions si présent (pour Choice/ChoiceList)
        col_data[:fields][:widgetOptions] = field_info[:grist_config][:widgetOptions].to_json if field_info[:grist_config]&.key?(:widgetOptions)

        columns_to_add << col_data
        existing_col_ids << col_id # Éviter les doublons dans le même batch
      end

      return if columns_to_add.empty?

      Rails.logger.info "GristSchemaBuilder: Création de #{columns_to_add.length} colonne(s)..."
      Rails.logger.debug { "GristSchemaBuilder: Body: #{{ columns: columns_to_add }.to_json}" }

      @client.create_columns(@doc_id, @table_id, { columns: columns_to_add })

      columns_to_add.each do |col|
        matching_field = fields_to_create.find { |f| sanitize_column_id(f[:field_name]) == col[:id] || f[:field_name] == col[:fields][:label] }
        @report[:fields_created] << {
          name: col[:fields][:label],
          original_label: matching_field&.dig(:original_label),
          type: col[:fields][:type],
          category: matching_field&.dig(:category)
        }
      end
    rescue Grist::APIError => e
      Rails.logger.error "GristSchemaBuilder: Échec création colonnes (HTTP #{e.status_code}): #{e.error_data}"
      @report[:errors] << "Échec création colonnes (HTTP #{e.status_code}): #{e.message}"
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def find_available_col_id(base_id, existing_ids)
      counter = 1
      counter += 1 while existing_ids.include?("#{base_id}_#{counter}")
      "#{base_id}_#{counter}"
    end

    # Convertit un label en ID de colonne Grist valide
    def sanitize_column_id(name)
      id = name.to_s.parameterize(separator: '_')
      id = "c_#{id}" if id.match?(/\A\d/)
      id
    end

    def identity_fields
      base_fields = base_system_fields

      case @options[:demandeur_type]
      when 'personne_physique'
        base_fields + personne_physique_fields
      when 'personne_morale'
        base_fields + personne_morale_fields
      else
        base_fields + personne_physique_fields + personne_morale_fields
      end
    end

    def base_system_fields
      [state_field] + date_fields + [email_usager_field, groupe_instructeur_field]
    end

    def state_field
      {
        original_label: 'state',
        field_name: 'Statut',
        mes_demarches_type: 'DropDownListChampDescriptor',
        category: 'système',
        supported: true,
        required: false,
        grist_type: 'Choice',
        grist_config: { widgetOptions: { choices: %w[en_construction en_instruction accepte refuse sans_suite] } }
      }
    end

    def date_fields
      date_field_configs.map { |config| build_date_field(config) }
    end

    def date_field_configs
      [
        { original: 'dateDepot', name: 'Date de depot' },
        { original: 'datePassageEnInstruction', name: 'Date de passage en instruction' },
        { original: 'dateTraitement', name: 'Date de traitement' },
        { original: 'dateDerniereModification', name: 'Date de derniere modification' }
      ]
    end

    def build_date_field(config)
      {
        original_label: config[:original],
        field_name: config[:name],
        mes_demarches_type: 'DatetimeChampDescriptor',
        category: 'système',
        supported: true,
        required: false,
        grist_type: 'DateTime:UTC',
        grist_config: {}
      }
    end

    def email_usager_field
      {
        original_label: 'usager.email',
        field_name: 'Email usager',
        mes_demarches_type: 'EmailChampDescriptor',
        category: 'système',
        supported: true,
        required: false,
        grist_type: 'Text',
        grist_config: {}
      }
    end

    def groupe_instructeur_field
      {
        original_label: 'groupeInstructeur.label',
        field_name: 'Groupe instructeur',
        mes_demarches_type: 'TextChampDescriptor',
        category: 'système',
        supported: true,
        required: false,
        grist_type: 'Text',
        grist_config: {}
      }
    end

    def personne_physique_fields
      [
        build_text_field('demandeur.civilite', 'Civilite'),
        build_text_field('demandeur.nom', 'Nom'),
        build_text_field('demandeur.prenom', 'Prenom')
      ]
    end

    def personne_morale_fields
      [
        build_text_field('demandeur.siret', 'Numero TAHITI'),
        build_text_field('demandeur.entreprise.raisonSociale', 'Raison sociale'),
        build_text_field('demandeur.entreprise.nomCommercial', 'Nom commercial'),
        build_text_field('demandeur.entreprise.formeJuridique', 'Forme juridique'),
        build_text_field('demandeur.libelleNaf', 'Libelle NAF')
      ]
    end

    def build_text_field(original_label, field_name)
      {
        original_label: original_label,
        field_name: field_name,
        mes_demarches_type: 'TextChampDescriptor',
        category: 'système',
        supported: true,
        required: false,
        grist_type: 'Text',
        grist_config: {}
      }
    end
  end
end
