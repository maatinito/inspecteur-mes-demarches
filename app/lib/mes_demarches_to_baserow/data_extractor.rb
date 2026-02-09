# frozen_string_literal: true

module MesDemarchesToBaserow
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

      # Champs système (toujours extraits)
      data.merge!(extract_system_fields(dossier))

      # Champs formulaire (toujours extraits)
      data.merge!(extract_champs(dossier))

      # Annotations privées (toujours extraites)
      data.merge!(extract_annotations(dossier))

      data
    end

    # rubocop:disable Metrics/MethodLength
    def extract_system_fields(dossier)
      data = {
        'Dossier' => dossier.number,
        'Statut' => dossier.state,
        'Date de dépôt' => format_datetime(dossier.date_depot),
        'Date de passage en instruction' => format_datetime(dossier.date_passage_en_instruction),
        'Date de traitement' => format_datetime(dossier.date_traitement),
        'Email usager' => dossier.usager&.email
      }

      # Extraction selon le type de demandeur (PersonnePhysique ou PersonneMorale)
      if dossier.demandeur
        demandeur_type = dossier.demandeur.respond_to?(:__typename) ? dossier.demandeur.__typename : nil

        case demandeur_type
        when 'PersonnePhysique'
          data.merge!(
            'Civilité' => dossier.demandeur.civilite,
            'Nom' => dossier.demandeur.nom,
            'Prénom' => dossier.demandeur.prenom
          )
        when 'PersonneMorale'
          data.merge!(
            'Numéro TAHITI' => dossier.demandeur.siret,
            'Raison sociale' => dossier.demandeur.entreprise&.raison_sociale,
            'Nom commercial' => dossier.demandeur.entreprise&.nom_commercial,
            'Forme juridique' => dossier.demandeur.entreprise&.forme_juridique,
            'Libellé NAF' => dossier.demandeur.libelle_naf
          )
        end
      end

      data.compact
    end
    # rubocop:enable Metrics/MethodLength

    def extract_champs(dossier)
      extract_fields(dossier.champs)
    end

    def extract_annotations(dossier)
      extract_fields(dossier.annotations)
    end

    def extract_fields(champs)
      data = {}

      champs.each do |champ|
        next if champ.__typename == 'RepetitionChamp'

        field_name = champ.label
        next unless @field_metadata.key?(field_name)

        baserow_type = @field_metadata[field_name]['type']

        # Pour les champs fichiers, passer les fichiers existants
        value = if baserow_type == 'file' && @existing_row
                  existing_files = @existing_row[field_name] || []
                  normalize_files(champ, existing_files)
                else
                  normalize_value(champ, baserow_type)
                end

        # Ne pas ajouter les champs avec des valeurs nil
        # (important pour les fichiers : si aucun nouveau fichier, on ne modifie pas le champ)
        data[field_name] = value unless value.nil?
      end

      data
    end

    def extract_repetable_blocks(dossier)
      blocks_data = {}

      # Auto-découvrir tous les champs de type RepetitionChamp dans champs ET annotations
      champs_repetition = find_all_repetition_champs(dossier.champs)
      annotations_repetition = find_all_repetition_champs(dossier.annotations)
      all_repetition_champs = champs_repetition + annotations_repetition

      all_repetition_champs.each do |repetition_champ|
        block_name = repetition_champ.label
        block_data = extract_block_rows(dossier, repetition_champ)
        blocks_data[block_name] = block_data if block_data.any?
      end

      blocks_data
    end

    def find_all_repetition_champs(champs)
      champs.select { |c| c.__typename == 'RepetitionChamp' }
    end

    def extract_block_rows(dossier, repetition_champ)
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

    def normalize_value(champ, baserow_type)
      case baserow_type
      when 'date'
        format_date(get_champ_value(champ))
      when 'boolean'
        normalize_boolean(get_champ_value(champ))
      when 'multiple_select'
        normalize_multiple_select(champ)
      when 'file'
        normalize_files(champ)
      when 'number'
        normalize_number(champ)
      else # single_select, phone_number, email, url, text, long_text
        get_champ_value(champ)
      end
    end

    def normalize_value_simple(champ)
      case champ.__typename
      when 'DateChamp', 'DatetimeChamp'
        format_date(get_champ_value(champ))
      when 'CheckboxChamp', 'YesNoChamp'
        normalize_boolean(get_champ_value(champ))
      when 'PieceJustificativeChamp'
        normalize_files(champ)
      when 'IntegerNumberChamp', 'DecimalNumberChamp'
        normalize_number(champ)
      else
        get_champ_value(champ)
      end
    end

    # Récupère la valeur d'un champ selon son type GraphQL
    # - Types simples (TextChamp, DateChamp, CheckboxChamp, etc.) utilisent 'value'
    # - Types spéciaux (SiretChamp, PieceJustificativeChamp, etc.) utilisent 'string_value'
    def get_champ_value(champ)
      # Priorité à 'value' (types simples), sinon 'string_value' (types spéciaux)
      champ.respond_to?(:value) ? champ.value : champ.string_value
    end

    def format_date(date_string)
      return nil if date_string.blank?

      # Format ISO8601 → format Baserow (YYYY-MM-DD)
      # Utiliser Date.parse pour obtenir uniquement la date sans l'heure
      Date.parse(date_string).iso8601
    rescue ArgumentError
      nil
    end

    def format_datetime(datetime_string)
      return nil if datetime_string.blank?

      # Format ISO8601 → format Baserow (YYYY-MM-DDTHH:MM:SSZ)
      # Convertir en UTC pour éviter les problèmes de timezone
      # Ex: 2025-11-18T08:40:08-10:00 → 2025-11-18T18:40:08Z
      DateTime.parse(datetime_string).utc.iso8601
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

    # rubocop:disable Metrics/MethodLength
    def normalize_files(champ, existing_files = [])
      return existing_files if champ.respond_to?(:files) && champ.files.blank?

      # Récupérer les fichiers existants dans Baserow
      # Format Baserow: [{ 'name' => 'hash...', 'url' => 'https://...', 'size' => 12345, 'visible_name' => '...' }]
      baserow_files = existing_files.is_a?(Array) ? existing_files : []

      # Construire un index des fichiers existants par (nom visible, taille)
      # avec leur hash Baserow pour réutilisation
      existing_file_index = baserow_files.map do |f|
        {
          visible_name: f['visible_name'],
          size: f['size'],
          baserow_hash: f['name'] # Le hash unique Baserow
        }
      end.compact

      # Pour CHAQUE fichier dans Mes-Démarches, déterminer s'il faut l'uploader ou le conserver
      all_files = champ.files.filter_map do |file|
        filename = file.filename.to_s.strip
        next if filename.blank?

        # Chercher si ce fichier existe déjà dans Baserow (même nom + même taille)
        existing = existing_file_index.find do |sig|
          sig[:visible_name] == filename && sig[:size] == file.byte_size
        end

        if existing
          # Fichier déjà uploadé : réutiliser le hash Baserow ET conserver le visible_name
          # Important : inclure visible_name pour éviter qu'il soit perdu dans Baserow
          { 'name' => existing[:baserow_hash], 'visible_name' => filename }
        else
          # Nouveau fichier : envoyer l'URL pour upload
          Rails.logger.debug "BaserowSync: Préparation upload nouveau fichier '#{filename}' depuis #{file.url}"
          { url: file.url, visible_name: filename }
        end
      end

      Rails.logger.info "BaserowSync: #{all_files.count { |f| f.key?(:url) }} nouveau(x) fichier(s) à uploader pour le champ #{champ.label}" if all_files.any? { |f| f.key?(:url) }

      # Si aucun fichier, retourner nil pour ne pas envoyer le champ
      all_files.empty? ? nil : all_files
    rescue StandardError => e
      Rails.logger.warn "BaserowSync: Erreur normalisation fichiers: #{e.message}"
      raise
    end
    # rubocop:enable Metrics/MethodLength

    def normalize_number(champ)
      value = get_champ_value(champ)
      return nil if value.blank?

      float_value = Float(value)
      # Si pas de décimales, retourner un Integer pour éviter les erreurs Baserow
      # sur les champs configurés avec number_decimal_places: 0
      (float_value % 1).zero? ? float_value.to_i : float_value
    rescue ArgumentError, TypeError
      nil
    end
  end
end
