# frozen_string_literal: true

module MesDemarchesToGrist
  # Gère l'upsert de rows dans Grist
  #
  # Simplifié par rapport à Baserow grâce à l'upsert natif Grist :
  # PUT /api/docs/{docId}/tables/{tableId}/records?noparse=true
  # avec { records: [{ require: {Dossier: n}, fields: data }] }
  class RowUpserter
    RETRYABLE_STATUS_CODES = [408, 429, 500, 502, 503, 504].freeze

    def initialize(table, options = {}, field_metadata = {}, dossier_col_id: 'Dossier')
      @table = table
      @options = options
      @field_metadata = field_metadata
      @dossier_col_id = dossier_col_id
      @retry_attempts = options['tentatives'] || 3
      @retry_delay = options['delai_retry'] || 5
    end

    # Upsert un record via l'API native Grist
    # Retourne l'id du record (existant ou créé)
    def upsert_row(dossier_number, data, existing_record: nil)
      upsert_with_retry(dossier_number, data, existing_record, 1)
    end

    private

    def upsert_with_retry(dossier_number, data, existing_record, attempt)
      # Optionnel : détecter les changements pour éviter un upsert inutile
      if existing_record
        changed_data = filter_changed_fields(data, existing_record)

        if changed_data.empty?
          Rails.logger.debug "GristSync: Aucun changement pour dossier #{dossier_number}"
          return existing_record['id']
        end

        data = changed_data
      else
        # Création : les nil sont écartés (rien à réinitialiser sur un nouveau record)
        data = data.compact
      end

      # Assurer que la colonne Dossier est dans les données
      data[@dossier_col_id] = dossier_number

      # Upsert natif Grist
      record = { require: { @dossier_col_id => dossier_number }, fields: data }
      @table.upsert_records([record])

      Rails.logger.info "GristSync: Upsert réussi pour dossier #{dossier_number} (#{data.keys.length} champ(s))"

      # Récupérer l'ID du record après upsert
      find_record_id(dossier_number)
    rescue Grist::APIError => e
      handle_api_error(e, dossier_number, data, existing_record, attempt)
    end

    def find_record_id(dossier_number)
      records = @table.find_by(@dossier_col_id, dossier_number)
      records.first&.dig('id')
    end

    # Filtre les champs pour ne retourner que ceux qui ont réellement changé.
    # Un champ vidé côté Mes-Démarches réinitialise la cellule Grist (via outgoing_value),
    # sauf les Attachments (nil = ne pas toucher, préservation des PJ).
    def filter_changed_fields(new_data, existing_record)
      existing_fields = existing_record['fields'] || {}
      changed_fields = {}

      new_data.each do |field_name, new_value|
        next unless @field_metadata.key?(field_name)

        col_type = @field_metadata[field_name][:type]
        next if col_type == 'Attachments' && new_value.nil?

        existing_value = existing_fields[field_name]
        changed_fields[field_name] = outgoing_value(new_value, col_type) if values_differ?(col_type, new_value, existing_value)
      end

      changed_fields
    end

    # Compare selon le type de colonne Grist
    def values_differ?(col_type, new_value, existing_value)
      case col_type
      when 'Integer', 'Numeric'
        values_differ_number?(new_value, existing_value)
      when 'ChoiceList'
        values_differ_choice_list?(new_value, existing_value)
      when 'Bool'
        values_differ_boolean?(new_value, existing_value)
      when 'Attachments'
        Array(new_value) != Array(existing_value)
      else # Choice, Text, Date, DateTime:UTC
        normalize_value(new_value) != normalize_value(existing_value)
      end
    end

    # Forme envoyée à Grist : un champ vidé côté Mes-Démarches réinitialise la
    # cellule (null pour Text/Choice/Date/Number/ChoiceList, false pour Bool).
    def outgoing_value(value, col_type)
      case col_type
      when 'Choice'
        value.presence
      when 'ChoiceList'
        choice_values(value).empty? ? nil : value
      when 'Bool'
        value.nil? ? false : value
      else
        value
      end
    end

    def normalize_value(value)
      return nil if value.nil? || value == '' || value == []

      value
    end

    def values_differ_number?(new_value, existing_value)
      return true if new_value.nil? != existing_value.nil?
      return false if new_value.nil?

      new_num = Float(new_value, exception: false)
      existing_num = Float(existing_value, exception: false)

      new_num != existing_num
    end

    # Grist ChoiceList : ["L", "val1", "val2"]
    # nil et ["L"] sont équivalents (liste vide)
    def values_differ_choice_list?(new_value, existing_value)
      choice_values(new_value) != choice_values(existing_value)
    end

    # Extrait les valeurs d'une ChoiceList en retirant le marqueur "L" de tête
    def choice_values(value)
      array = Array(value)
      array.first == 'L' ? array[1..] : array
    end

    # Compare Bool : nil équivaut à false (champ vidé → case décochée)
    def values_differ_boolean?(new_value, existing_value)
      (new_value || false) != (existing_value || false)
    end

    def handle_api_error(error, dossier_number, data, existing_record, attempt)
      if attempt < @retry_attempts && retryable_error?(error)
        delay = @retry_delay * (2**(attempt - 1))
        Rails.logger.warn "GristSync: Retry #{attempt}/#{@retry_attempts} après #{delay}s pour dossier #{dossier_number}: #{error.message}"
        sleep delay
        upsert_with_retry(dossier_number, data, existing_record, attempt + 1)
      else
        Rails.logger.error "GristSync: Échec synchro dossier #{dossier_number} après #{attempt} tentatives: #{error.message}"
        Sentry.capture_exception(error, extra: { dossier: dossier_number, data: data, attempt: attempt })

        raise unless @options['continuer_si_erreur']

        nil
      end
    end

    def retryable_error?(error)
      return false unless error.respond_to?(:status_code)

      RETRYABLE_STATUS_CODES.include?(error.status_code)
    end
  end
end
