# frozen_string_literal: true

module BaserowSync
  # Extrait les données d'un dossier Mes-Démarches pour synchronisation Baserow
  #
  # Responsabilités:
  # - Extraire les champs système (état, dates, usager)
  # - Extraire les champs formulaire
  # - Extraire les annotations privées
  # - Extraire les blocs répétables
  # - Normaliser les valeurs selon les types Baserow
  class DataExtractor
    def initialize(field_metadata, options = {})
      @field_metadata = field_metadata
      @options = options
      @existing_row = nil
    end

    def extract_all(dossier, existing_row = nil)
      @existing_row = existing_row

      {
        main_table: extract_main_table(dossier),
        repetable_blocks: extract_repetable_blocks(dossier)
      }
    end

    private

    def extract_main_table(dossier)
      data = {}

      # Champs système
      data.merge!(extract_system_fields(dossier)) if @options['include_system_fields']

      # Champs formulaire
      data.merge!(extract_champs(dossier))

      # Annotations privées
      data.merge!(extract_annotations(dossier)) if @options['include_annotations']

      data
    end

    def extract_system_fields(dossier)
      {
        'Dossier' => dossier.number,
        'Etat' => dossier.state,
        'Date dépôt' => format_date(dossier.datePassageEnConstruction),
        'Date instruction' => format_date(dossier.datePassageEnInstruction),
        'Date traitement' => format_date(dossier.dateTraitement),
        'Email usager' => dossier.usager&.email,
        'Demandeur civilité' => dossier.demandeur&.civilite,
        'Demandeur nom' => dossier.demandeur&.nom,
        'Demandeur prénom' => dossier.demandeur&.prenom,
        'SIRET' => dossier.demandeur&.siret
      }.compact
    end

    def extract_champs(dossier)
      extract_fields(dossier.champs)
    end

    def extract_annotations(dossier)
      extract_fields(dossier.annotations)
    end

    def extract_fields(champs)
      data = {}

      champs.each do |champ|
        next if champ.typename == 'RepetitionChamp'

        field_name = champ.label
        next unless @field_metadata.key?(field_name)

        baserow_type = @field_metadata[field_name]['type']

        # Pour les champs fichiers, passer les fichiers existants
        if baserow_type == 'file' && @existing_row
          existing_files = @existing_row[field_name] || []
          data[field_name] = normalize_files(champ, existing_files)
        else
          data[field_name] = normalize_value(champ, baserow_type)
        end
      end

      data
    end

    def extract_repetable_blocks(dossier)
      return {} unless @options['include_repetable_blocks']

      blocks_config = @options['repetable_blocks'] || []
      blocks_data = {}

      blocks_config.each do |block_config|
        block_data = extract_block(dossier, block_config)
        blocks_data[block_config['table_name']] = block_data if block_data.any?
      end

      blocks_data
    end

    def extract_block(dossier, block_config)
      # Trouver le champ répétable par ID
      repetition_champ = find_champ_by_id(dossier.champs, block_config['champ_id'])
      return [] unless repetition_champ

      rows = []
      repetition_champ.rows.each_with_index do |row, index|
        ligne_number = index + 1
        row_data = {
          'Ligne' => ligne_number,
          'Dossier' => dossier.number.to_s
        }

        # Extraire les champs de la row
        row.champs.each do |champ|
          field_name = champ.label
          # Pour les blocs, on utilise tous les champs (pas de filtrage par metadata)
          row_data[field_name] = normalize_value_simple(champ)
        end

        rows << row_data
      end

      rows
    end

    def find_champ_by_id(champs, champ_id)
      champs.find { |c| c.id == champ_id }
    end

    def normalize_value(champ, baserow_type)
      case baserow_type
      when 'date'
        format_date(champ.stringValue)
      when 'boolean'
        normalize_boolean(champ.stringValue)
      when 'multiple_select'
        normalize_multiple_select(champ)
      when 'file'
        normalize_files(champ)
      when 'number'
        normalize_number(champ)
      else # single_select, phone_number, email, url, text, long_text
        champ.stringValue
      end
    end

    def normalize_value_simple(champ)
      case champ.typename
      when 'DateChamp', 'DatetimeChamp'
        format_date(champ.stringValue)
      when 'CheckboxChamp', 'YesNoChamp'
        normalize_boolean(champ.stringValue)
      when 'PieceJustificativeChamp'
        normalize_files(champ)
      when 'IntegerNumberChamp', 'DecimalNumberChamp'
        normalize_number(champ)
      else
        champ.stringValue
      end
    end

    def format_date(date_string)
      return nil if date_string.blank?

      # Format ISO8601 → format Baserow (YYYY-MM-DD ou YYYY-MM-DDTHH:MM:SS)
      DateTime.parse(date_string).iso8601
    rescue ArgumentError
      nil
    end

    def normalize_boolean(value)
      return nil if value.blank?

      value.to_s.downcase.in?(%w[oui true 1 yes])
    end

    def normalize_multiple_select(champ)
      return [] if champ.values.blank?

      champ.values.map(&:to_s)
    end

    def normalize_files(champ, existing_files = [])
      return existing_files if champ.respond_to?(:files) && champ.files.blank?

      # Récupérer les fichiers existants dans Baserow
      # Format Baserow: [{ 'name' => 'file.pdf', 'url' => 'https://...', 'size' => 12345, 'visible_name' => '...' }]
      baserow_files = existing_files.is_a?(Array) ? existing_files : []

      # Construire un index des fichiers existants par (nom, taille)
      # pour détecter les fichiers identiques même si l'URL change
      existing_file_signatures = baserow_files.map do |f|
        {
          name: f['name'] || f['visible_name'],
          size: f['size']
        }
      end.compact

      # Ajouter uniquement les nouveaux fichiers (par nom + taille)
      champ.files.filter_map do |file|
        # Vérifier si un fichier avec le même nom ET la même taille existe déjà
        file_exists = existing_file_signatures.any? do |sig|
          sig[:name] == file.filename && sig[:size] == file.byte_size
        end

        next if file_exists

        {
          name: file.filename,
          url: file.url
        }
      end

      # Retourner uniquement les nouveaux fichiers à ajouter
      # Important: Baserow attend juste les nouveaux fichiers avec URL pour les ajouter
      # Les fichiers déjà uploadés restent en place automatiquement
    rescue StandardError => e
      Rails.logger.warn "BaserowSync: Erreur normalisation fichiers: #{e.message}"
      []
    end

    def normalize_number(champ)
      return nil if champ.stringValue.blank?

      Float(champ.stringValue)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
