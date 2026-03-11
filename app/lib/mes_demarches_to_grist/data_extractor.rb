# frozen_string_literal: true

module MesDemarchesToGrist
  # Extrait les données d'un dossier Mes-Démarches pour synchronisation Grist
  #
  # Différences clés avec Baserow :
  # - Dates → timestamp Unix (epoch seconds)
  # - Booleans → true/false natif
  # - ChoiceList → ["L", "val1", "val2"] (encoding Grist)
  # - Fichiers → {url:, visible_name:} (upload géré par SyncCoordinator)
  class DataExtractor
    def initialize(field_metadata, options = {}, attachment_metadata: {})
      @field_metadata = field_metadata
      @options = options
      @attachment_metadata = attachment_metadata || {}
    end

    def extract_all(dossier, _existing_row = nil)
      {
        main_table: extract_main_table(dossier),
        repetable_blocks: extract_repetable_blocks(dossier)
      }
    end

    private

    def extract_main_table(dossier)
      data = {}
      data.merge!(extract_system_fields(dossier))
      data.merge!(extract_champs(dossier))
      data.merge!(extract_annotations(dossier))
      data
    end

    # rubocop:disable Metrics/MethodLength
    def extract_system_fields(dossier)
      data = {
        'Dossier' => dossier.number,
        'Statut' => dossier.state,
        'Date de depot' => format_datetime_epoch(dossier.date_depot),
        'Date de passage en instruction' => format_datetime_epoch(dossier.date_passage_en_instruction),
        'Date de traitement' => format_datetime_epoch(dossier.date_traitement),
        'Email usager' => dossier.usager&.email,
        'Groupe instructeur' => dossier.groupe_instructeur&.label
      }

      if dossier.demandeur
        demandeur_type = dossier.demandeur.respond_to?(:__typename) ? dossier.demandeur.__typename : nil

        case demandeur_type
        when 'PersonnePhysique'
          data.merge!(
            'Civilite' => dossier.demandeur.civilite,
            'Nom' => dossier.demandeur.nom,
            'Prenom' => dossier.demandeur.prenom
          )
        when 'PersonneMorale'
          data.merge!(
            'Numero TAHITI' => dossier.demandeur.siret,
            'Raison sociale' => dossier.demandeur.entreprise&.raison_sociale,
            'Nom commercial' => dossier.demandeur.entreprise&.nom_commercial,
            'Forme juridique' => dossier.demandeur.entreprise&.forme_juridique,
            'Libelle NAF' => dossier.demandeur.libelle_naf
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

        grist_type = @field_metadata[field_name][:type]

        value = if grist_type == 'Attachments'
                  normalize_files(champ, @attachment_metadata[field_name])
                else
                  normalize_value(champ, grist_type)
                end

        data[field_name] = value unless value.nil?
      end

      data
    end

    def extract_repetable_blocks(dossier)
      blocks_data = {}

      all_repetition_champs = find_all_repetition_champs(dossier.champs) +
                              find_all_repetition_champs(dossier.annotations)

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
          'Dossier' => dossier.number
        }

        row.champs.each do |champ|
          field_name = champ.label
          row_data[field_name] = normalize_value_simple(champ)
        end

        rows << row_data
      end

      rows
    end

    def normalize_value(champ, grist_type)
      case grist_type
      when 'Date'
        format_date_epoch(get_champ_value(champ))
      when 'DateTime:UTC'
        format_datetime_epoch(get_champ_value(champ))
      when 'Bool'
        normalize_boolean(get_champ_value(champ))
      when 'ChoiceList'
        normalize_choice_list(champ)
      when 'Attachments'
        normalize_files(champ)
      when 'Integer'
        normalize_integer(champ)
      when 'Numeric'
        normalize_numeric(champ)
      else # Choice, Text
        get_champ_value(champ)
      end
    end

    def normalize_value_simple(champ)
      case champ.__typename
      when 'DateChamp'
        format_date_epoch(get_champ_value(champ))
      when 'DatetimeChamp'
        format_datetime_epoch(get_champ_value(champ))
      when 'CheckboxChamp', 'YesNoChamp'
        normalize_boolean(get_champ_value(champ))
      when 'PieceJustificativeChamp'
        normalize_files(champ)
      when 'IntegerNumberChamp'
        normalize_integer(champ)
      when 'DecimalNumberChamp'
        normalize_numeric(champ)
      else
        get_champ_value(champ)
      end
    end

    def get_champ_value(champ)
      champ.respond_to?(:value) ? champ.value : champ.string_value
    end

    # Grist attend les dates en timestamp Unix (epoch seconds)
    def format_date_epoch(date_string)
      return nil if date_string.blank?

      Date.parse(date_string).to_time.to_i
    rescue ArgumentError
      nil
    end

    def format_datetime_epoch(datetime_string)
      return nil if datetime_string.blank?

      DateTime.parse(datetime_string).to_time.to_i
    rescue ArgumentError
      nil
    end

    def normalize_boolean(value)
      return nil if value.blank?

      value.to_s.downcase.in?(%w[oui true 1 yes])
    end

    # Grist ChoiceList encoding : ["L", "val1", "val2"]
    def normalize_choice_list(champ)
      return ['L'] if champ.values.blank?

      ['L'] + champ.values.map(&:to_s)
    end

    # Compare les fichiers Mes-Démarches avec les attachments existants dans Grist.
    # Réutilise les attachment_id existants si nom + taille identiques,
    # ne prépare l'upload que pour les fichiers nouveaux/modifiés.
    def normalize_files(champ, existing_attachments = nil)
      return nil if champ.respond_to?(:files) && champ.files.blank?

      existing_index = (existing_attachments || []).map do |att|
        { id: att[:id], fileName: att[:fileName], fileSize: att[:fileSize] }
      end

      all_files = champ.files.filter_map do |file|
        filename = file.filename.to_s.strip
        next if filename.blank?

        existing = existing_index.find do |att|
          att[:fileName] == filename && att[:fileSize] == file.byte_size
        end

        if existing
          { existing_id: existing[:id], visible_name: filename }
        else
          { url: file.url, visible_name: filename }
        end
      end

      new_count = all_files.count { |f| f.key?(:url) }
      Rails.logger.info "GristSync: #{new_count} nouveau(x) fichier(s) à uploader pour #{champ.label}" if new_count.positive?

      all_files.empty? ? nil : all_files
    rescue StandardError => e
      Rails.logger.warn "GristSync: Erreur normalisation fichiers: #{e.message}"
      raise
    end

    def normalize_integer(champ)
      value = get_champ_value(champ)
      return nil if value.blank?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_numeric(champ)
      value = get_champ_value(champ)
      return nil if value.blank?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
