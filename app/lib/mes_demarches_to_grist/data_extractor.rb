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
    # Types de champs à ne jamais synchroniser (même règle que Baserow).
    # TitreIdentiteChamp : pièce d'identité, confidentialité.
    IGNORED_CHAMP_TYPES = %w[TitreIdentiteChamp].freeze

    # Types décoratifs sans valeur : leur nil ne doit jamais vider une cellule.
    DECORATIVE_CHAMP_TYPES = %w[HeaderSectionChamp ExplicationChamp].freeze

    # Erreurs de lecture d'un champ GraphQL : le champ est ignoré (cellule laissée
    # intacte) plutôt que de propager un nil qui viderait la cellule Grist.
    # UnfetchedFieldError hérite de NoMethodError, pas de GraphQL::Client::Error.
    CHAMP_READ_ERRORS = [GraphQL::Client::Error, GraphQL::Client::UnfetchedFieldError].freeze

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

    # Métadonnées système + identité demandeur, depuis la source unique
    # SchemaBuilders::MetadataFields (noms uniformes Grist/Baserow). Le mode
    # demandeur vient du __typename du dossier (jamais mixte sur une démarche).
    def extract_system_fields(dossier)
      typename = dossier.demandeur.respond_to?(:__typename) ? dossier.demandeur&.__typename : nil
      modes = [SchemaBuilders::MetadataFields.mode_for_typename(typename)].compact

      # Les nil sont conservés : une métadonnée redevenue vide (ex: date de
      # traitement après repassage en instruction) réinitialise la cellule Grist.
      SchemaBuilders::MetadataFields.all(modes).to_h do |field|
        [field.name, format_metadata_value(field, field.source.call(dossier))]
      end
    end

    # Mise en forme Grist : dates → epoch ; multi-choix → encoding ChoiceList
    # ["L", ...] ; sinon valeur brute.
    def format_metadata_value(field, raw)
      return nil if raw.nil?

      if field.datetime?
        format_datetime_epoch(raw)
      elsif field.multiple?
        names = Array(raw).map { |l| l.respond_to?(:name) ? l.name : l.to_s }
        names.empty? ? nil : (['L'] + names)
      else
        raw
      end
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
        next if champ.__typename == 'RepetitionChamp'
        next if IGNORED_CHAMP_TYPES.include?(champ.__typename)
        next if DECORATIVE_CHAMP_TYPES.include?(champ.__typename)

        field_name = champ.label
        next unless @field_metadata.key?(field_name)

        grist_type = @field_metadata[field_name][:type]

        value = if grist_type == 'Attachments'
                  normalize_files(champ, @attachment_metadata[field_name])
                else
                  normalize_value(champ, grist_type)
                end

        # Les nil sont conservés : ils signifient « champ vidé côté Mes-Démarches »
        # et déclenchent la réinitialisation de la cellule Grist dans RowUpserter.
        # Exception : Attachments (nil = ne pas toucher, préservation des PJ).
        data[field_name] = value unless grist_type == 'Attachments' && value.nil?
      rescue *CHAMP_READ_ERRORS => e
        Rails.logger.warn("GristSync: champ #{field_name} illisible (#{champ.__typename}), cellule laissée intacte — #{e.message}")
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
          next if IGNORED_CHAMP_TYPES.include?(champ.__typename)
          next if DECORATIVE_CHAMP_TYPES.include?(champ.__typename)

          field_name = champ.label
          row_data[field_name] = normalize_value_simple(champ)
        rescue *CHAMP_READ_ERRORS => e
          Rails.logger.warn("GristSync: champ de bloc #{field_name} illisible (#{champ.__typename}), ignoré — #{e.message}")
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
      when 'Choice'
        # Un Choice vide devient nil (RowUpserter enverra null pour réinitialiser
        # la cellule — même philosophie que single_select côté Baserow)
        get_champ_value(champ).presence
      else # Text
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
        normalize_boolean(champ.checked)
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
      return nil if %w[HeaderSectionChamp ExplicationChamp].include?(champ.__typename)

      case champ.__typename
      when 'IntegerNumberChamp' then champ.int_value
      when 'DecimalNumberChamp' then champ.decimal_value
      when 'DateChamp' then champ.date_value
      when 'CiviliteChamp' then champ.civilite_value
      when 'CheckboxChamp', 'YesNoChamp' then champ.checked
      else
        champ.respond_to?(:value) ? champ.value : champ.string_value
      end
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
      # Ne pas utiliser blank? en premier : false.blank? == true, or une case
      # décochée doit bien repasser à false dans Grist.
      return value if [true, false].include?(value)
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
