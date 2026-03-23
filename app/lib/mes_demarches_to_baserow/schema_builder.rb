# frozen_string_literal: true

module MesDemarchesToBaserow
  class SchemaBuilder
    class SchemaError < StandardError; end

    attr_reader :demarche_number, :table_id, :options, :report

    def initialize(demarche_number, table_id, options = {})
      @demarche_number = demarche_number
      @table_id = table_id
      @options = default_options.merge(options)
      @type_mapper = TypeMapper.new
      @structure_client = Baserow::StructureClient.new
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
        existing_fields: fields_to_create.count { |f| f[:exists_in_baserow] },
        new_fields: fields_to_create.count { |f| !f[:exists_in_baserow] },
        supported_fields: fields_to_create.count { |f| f[:supported] },
        unsupported_fields: fields_to_create.count { |f| !f[:supported] },
        fields: fields_to_create
      }
    end

    def build!(selected_fields: nil)
      validate_demarche_access!

      # Valider le champ primaire mais ne pas bloquer la construction
      primary_validation = validate_primary_field_soft

      fields_to_create = collect_fields_to_create.select { |f| f[:supported] }

      # Filtrer par sélection utilisateur
      fields_to_create.select! { |f| selected_fields.include?(f[:field_name]) } if selected_fields.present?

      # Warning si aucun champ sélectionné
      if fields_to_create.empty?
        @report[:warnings] ||= []
        @report[:warnings] << 'Aucun champ sélectionné pour la création'
        return @report
      end

      fields_to_create.each do |field_info|
        create_field_if_needed(field_info)
      end

      # Ajouter l'avertissement du champ primaire au rapport si nécessaire
      @report[:primary_field_warning] = primary_validation[:error] if primary_validation && !primary_validation[:valid]

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

    def validate_primary_field!
      validation = @structure_client.validate_primary_field(@table_id)

      return if validation[:valid]

      raise SchemaError, "❌ Validation du champ primaire échouée: #{validation[:error]}\n\n" \
                         "🔧 Pour résoudre ce problème:\n" \
                         "1. Renommez le champ primaire en 'Dossier'\n" \
                         "2. Assurez-vous qu'il soit de type 'number'\n" \
                         '3. Ce champ doit contenir les numéros de dossier Mes-Démarches'
    end

    # Version non bloquante de la validation du champ primaire
    def validate_primary_field_soft
      @structure_client.validate_primary_field(@table_id)
    end

    def mark_existing_fields(fields)
      # Récupérer tous les champs existants UNE SEULE FOIS pour éviter les multiples appels API
      existing_fields = @structure_client.get_table_fields(@table_id)
      existing_field_names = Set.new(existing_fields.map { |f| f['name']&.downcase })

      fields.each do |field_info|
        field_info[:exists_in_baserow] = existing_field_names.include?(field_info[:field_name].downcase)
        field_info[:is_mandatory] = (field_info[:field_name] == 'Dossier')
      end
    rescue Baserow::APIError
      # En cas d'erreur API, marquer tous les champs comme non-existants
      fields.each do |field_info|
        field_info[:exists_in_baserow] = false
        field_info[:is_mandatory] = (field_info[:field_name] == 'Dossier')
      end
    end

    def collect_fields_to_create
      demarche = validate_demarche_access!

      # Priorité à la draft revision, sinon published revision
      revision = demarche.draft_revision || demarche.published_revision

      raise SchemaError, "Démarche #{@demarche_number} n'a ni révision en brouillon ni révision publiée disponible" unless revision

      fields = []

      # Traiter les informations système en premier pour un ordre logique dans Baserow
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
      add_baserow_mapping(field_info, field_type, descriptor) if supported
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

    def add_baserow_mapping(field_info, field_type, descriptor)
      mapping = @type_mapper.map_field_type(field_type, descriptor.to_h)
      field_info[:baserow_type] = mapping[:type]
      field_info[:baserow_config] = mapping[:config]
    rescue TypeMapper::UnsupportedTypeError => e
      field_info[:supported] = false
      field_info[:error] = e.message
    end

    def identity_fields
      base_fields = base_system_fields

      case @options[:demandeur_type]
      when 'personne_physique'
        base_fields + personne_physique_fields
      when 'personne_morale'
        base_fields + personne_morale_fields
      else # 'mixte' ou autre
        base_fields + personne_physique_fields + personne_morale_fields
      end
    end

    def base_system_fields
      # Ne pas inclure primary_field car il doit déjà exister dans la table
      # La validation se fait dans validate_primary_field_soft
      [state_field] + date_fields + [email_usager_field, labels_field]
    end

    def primary_field
      {
        original_label: 'number',
        field_name: 'Dossier',
        mes_demarches_type: 'IntegerNumberChampDescriptor',
        category: 'système',
        supported: true,
        required: true,
        baserow_type: 'number',
        baserow_config: { number_decimal_places: 0 },
        primary: true
      }
    end

    def state_field
      {
        original_label: 'state',
        field_name: 'Statut',
        mes_demarches_type: 'DropDownListChampDescriptor',
        category: 'système',
        supported: true,
        required: false,
        baserow_type: 'single_select',
        baserow_config: state_select_options
      }
    end

    def state_select_options
      {
        select_options: [
          { value: 'en_construction', color: 'blue' },
          { value: 'en_instruction', color: 'orange' },
          { value: 'accepte', color: 'green' },
          { value: 'refuse', color: 'red' },
          { value: 'sans_suite', color: 'gray' }
        ]
      }
    end

    def date_fields
      date_field_configs.map { |config| build_date_field(config) }
    end

    def date_field_configs
      [
        { original: 'dateDepot', name: 'Date de dépôt' },
        { original: 'datePassageEnInstruction', name: 'Date de passage en instruction' },
        { original: 'dateTraitement', name: 'Date de traitement' }
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
        baserow_type: 'date',
        baserow_config: { date_format: 'EU', date_include_time: true }
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
        baserow_type: 'email',
        baserow_config: {}
      }
    end

    def labels_field
      {
        original_label: 'labels',
        field_name: 'Labels',
        mes_demarches_type: 'MultipleDropDownListChampDescriptor',
        category: 'système',
        supported: true,
        required: false,
        baserow_type: 'multiple_select',
        baserow_config: {
          select_options: []
        }
      }
    end

    def personne_physique_fields
      demandeur_physique_fields + mandataire_fields
    end

    def demandeur_physique_fields
      [
        build_text_field('demandeur.civilite', 'Civilité'),
        build_text_field('demandeur.nom', 'Nom'),
        build_text_field('demandeur.prenom', 'Prénom')
      ]
    end

    def mandataire_fields
      [
        build_text_field('prenomMandataire', 'Prénom mandataire'),
        build_text_field('nomMandataire', 'Nom mandataire'),
        build_boolean_field('deposeParUnTiers', 'Déposé par un tiers')
      ]
    end

    def personne_morale_fields
      etablissement_fields
    end

    def etablissement_fields
      etablissement_configs.map { |config| build_text_field(config[:original], config[:name]) }
    end

    def etablissement_configs
      [
        { original: 'demandeur.siret', name: 'Numéro TAHITI' },
        { original: 'demandeur.entreprise.raisonSociale', name: 'Raison sociale' },
        { original: 'demandeur.entreprise.nomCommercial', name: 'Nom commercial' },
        { original: 'demandeur.entreprise.formeJuridique', name: 'Forme juridique' },
        { original: 'demandeur.libelleNaf', name: 'Libellé NAF' }
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
        baserow_type: 'text',
        baserow_config: {}
      }
    end

    def build_email_field(original_label, field_name)
      {
        original_label: original_label,
        field_name: field_name,
        mes_demarches_type: 'EmailChampDescriptor',
        category: 'système',
        supported: true,
        required: false,
        baserow_type: 'email',
        baserow_config: {}
      }
    end

    def build_boolean_field(original_label, field_name)
      {
        original_label: original_label,
        field_name: field_name,
        mes_demarches_type: 'CheckboxChampDescriptor',
        category: 'système',
        supported: true,
        required: false,
        baserow_type: 'boolean',
        baserow_config: {}
      }
    end

    def create_field_if_needed(field_info)
      field_name = field_info[:field_name]

      if @structure_client.field_exists?(@table_id, field_name)
        # Vérifier si c'est un dropdown et si on peut mettre à jour les options
        if should_update_dropdown_options?(field_info)
          update_dropdown_options(field_info)
          return
        end

        case @options[:collision_strategy]
        when 'skip'
          @report[:fields_skipped] << { name: field_name, reason: 'field_exists' }
          return
        when 'error'
          raise SchemaError, "Le champ '#{field_name}' existe déjà dans la table"
        when 'rename'
          field_name = find_available_name(field_name)
          field_info[:field_name] = field_name
        end
      end

      create_baserow_field(field_info)
    end

    def find_available_name(base_name)
      counter = 1
      counter += 1 while @structure_client.field_exists?(@table_id, "#{base_name}_#{counter}")
      "#{base_name}_#{counter}"
    end

    def create_baserow_field(field_info)
      field_data = {
        type: field_info[:baserow_type],
        name: field_info[:field_name]
      }

      field_data.merge!(field_info[:baserow_config]) if field_info[:baserow_config].any?

      @structure_client.create_field(@table_id, field_data)
      @report[:fields_created] << {
        name: field_info[:field_name],
        original_label: field_info[:original_label],
        type: field_info[:baserow_type],
        category: field_info[:category]
      }
    rescue Baserow::APIError => e
      @report[:fields_failed] << {
        name: field_info[:field_name],
        error: e.message
      }
      @report[:errors] << "Échec création champ '#{field_info[:field_name]}': #{e.message}"
    end

    def should_update_dropdown_options?(field_info)
      # Seulement pour les dropdown supportés
      return false unless %w[DropDownListChampDescriptor MultipleDropDownListChampDescriptor].include?(field_info[:mes_demarches_type])
      return false unless field_info[:supported]

      # Vérifier que le champ existant est bien un dropdown
      existing_field = @structure_client.get_field_by_name(@table_id, field_info[:field_name])
      return false unless existing_field

      %w[single_select multiple_select].include?(existing_field['type'])
    end

    def update_dropdown_options(field_info)
      field_name = field_info[:field_name]
      existing_field = @structure_client.get_field_by_name(@table_id, field_name)

      # Récupérer les options existantes
      existing_options = existing_field['select_options'] || []
      existing_values = existing_options.map { |opt| opt['value'] }

      # Récupérer les nouvelles options de Mes-Démarches
      new_options = field_info[:baserow_config][:select_options] || []

      # Identifier les nouvelles options à ajouter
      options_to_add = new_options.reject { |new_opt| existing_values.include?(new_opt[:value]) }

      if options_to_add.any?
        # Fusionner les options : garder les existantes + ajouter les nouvelles
        updated_options = existing_options + options_to_add.map(&:stringify_keys)

        # Mettre à jour le champ avec les nouvelles options
        update_data = { select_options: updated_options }
        @structure_client.update_field(existing_field['id'], update_data)

        @report[:fields_updated] ||= []
        @report[:fields_updated] << {
          name: field_name,
          action: 'options_added',
          new_options: options_to_add.map { |opt| opt[:value] }
        }
      else
        @report[:fields_skipped] << { name: field_name, reason: 'options_up_to_date' }
      end
    rescue Baserow::APIError => e
      @report[:fields_failed] << {
        name: field_name,
        error: "Échec mise à jour options: #{e.message}"
      }
    end
  end
end
