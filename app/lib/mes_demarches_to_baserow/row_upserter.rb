# frozen_string_literal: true

module MesDemarchesToBaserow
  # Gère l'insertion et la mise à jour de rows dans Baserow
  #
  # Responsabilités:
  # - Déterminer si une row existe déjà (par numéro de dossier)
  # - Créer une nouvelle row si nécessaire
  # - Mettre à jour une row existante
  # - Gérer les erreurs avec retry et backoff exponentiel
  class RowUpserter
    RETRYABLE_STATUS_CODES = [408, 429, 500, 502, 503, 504].freeze

    def initialize(table, options = {}, field_metadata = {})
      @table = table
      @options = options
      @field_metadata = field_metadata
      @retry_attempts = options['tentatives'] || 3
      @retry_delay = options['delai_retry'] || 5
    end

    def upsert_row(dossier_number, data, existing_row: :not_provided)
      upsert_row_with_retry(dossier_number, data, existing_row, 1)
    end

    private

    def upsert_row_with_retry(dossier_number, data, existing_row, attempt)
      # Chercher la row seulement si pas déjà fournie (y compris si fournie comme nil)
      existing_row = find_existing_row(dossier_number) if existing_row == :not_provided

      if existing_row
        # Filtrer pour n'envoyer que les champs modifiés (évite pollution historique Baserow)
        changed_data = filter_changed_fields(data, existing_row)

        if changed_data.empty?
          Rails.logger.debug "BaserowSync: Aucun changement pour dossier #{dossier_number}"
        else
          @table.update_row(existing_row['id'], changed_data)
          Rails.logger.info "BaserowSync: Row mise à jour (dossier #{dossier_number}, #{changed_data.keys.length} champ(s) modifié(s))"
        end

        existing_row['id']
      else
        # S'assurer que le champ Dossier est présent
        data_with_dossier = data.merge('Dossier' => dossier_number)
        new_row = @table.create_row(data_with_dossier)
        Rails.logger.info "BaserowSync: Row créée (dossier #{dossier_number}, row_id #{new_row['id']})"

        new_row['id']
      end
    rescue Baserow::APIError => e
      handle_api_error(e, dossier_number, data, existing_row, attempt)
    end

    def find_existing_row(dossier_number)
      # Chercher par champ "Dossier" avec user_field_names=true pour la comparaison
      results = @table.find_by_normalized('Dossier', dossier_number.to_s)
      results.first
    rescue StandardError => e
      Rails.logger.error "BaserowSync: Erreur recherche row (dossier #{dossier_number}): #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise # Re-lever pour que l'erreur soit visible et gérée
    end

    # Filtre les champs pour ne retourner que ceux qui ont réellement changé
    # Compare intelligemment selon le type Baserow pour éviter les faux positifs
    def filter_changed_fields(new_data, existing_row)
      changed_fields = {}

      new_data.each do |field_name, new_value|
        # Skip si le champ n'existe pas dans Baserow (colonne absente)
        next unless @field_metadata.key?(field_name)

        existing_value = existing_row[field_name]
        field_type = @field_metadata[field_name]['type']

        # Comparer selon le type de champ
        has_changed = case field_type
                      when 'number'
                        values_differ_number?(new_value, existing_value)
                      when 'single_select'
                        values_differ_single_select?(new_value, existing_value)
                      when 'multiple_select'
                        values_differ_multiple_select?(new_value, existing_value)
                      when 'file'
                        values_differ_file?(new_value, existing_value)
                      when 'link_row'
                        values_differ_link_row?(new_value, existing_value)
                      when 'phone_number'
                        values_differ_phone_number?(new_value, existing_value)
                      else
                        # Pour text, long_text, date, boolean, email, url
                        # Comparaison directe (en normalisant nil vs vide)
                        normalize_value(new_value) != normalize_value(existing_value)
                      end

        changed_fields[field_name] = new_value if has_changed
      end

      changed_fields
    end

    # Normalise une valeur pour comparaison (traite nil, "", [] comme équivalents)
    def normalize_value(value)
      return nil if value.nil? || value == '' || value == []

      value
    end

    # Compare deux valeurs numériques (Baserow peut retourner string ou nombre)
    def values_differ_number?(new_value, existing_value)
      return true if new_value.nil? != existing_value.nil?
      return false if new_value.nil?

      new_num = Float(new_value, exception: false)
      existing_num = Float(existing_value, exception: false)

      new_num != existing_num
    end

    # Compare single_select : new est une string, existing est { "id" => X, "value" => "..." }
    def values_differ_single_select?(new_value, existing_value)
      return true if new_value.nil? != existing_value.nil?
      return false if new_value.nil?

      existing_str = existing_value.is_a?(Hash) ? existing_value['value'] : existing_value
      new_value.to_s != existing_str.to_s
    end

    # Compare multiple_select : new est [strings], existing est [{ "id" => X, "value" => "..." }]
    def values_differ_multiple_select?(new_value, existing_value)
      new_array = Array(new_value).compact
      existing_array = Array(existing_value).compact

      return true if new_array.length != existing_array.length

      # Extraire les values de existing
      existing_values = existing_array.map { |item| item.is_a?(Hash) ? item['value'] : item }.sort
      new_values = new_array.map(&:to_s).sort

      new_values != existing_values
    end

    # Compare files : arrays de hashes avec 'name' (hash Baserow unique)
    def values_differ_file?(new_value, existing_value)
      new_array = Array(new_value).compact
      existing_array = Array(existing_value).compact

      return true if new_array.length != existing_array.length

      # Comparer les 'name' (hashes Baserow) triés
      new_names = new_array.map { |f| f['name'] }.compact.sort
      existing_names = existing_array.map { |f| f['name'] }.compact.sort

      new_names != existing_names
    end

    # Compare link_row : arrays d'IDs
    def values_differ_link_row?(new_value, existing_value)
      new_array = Array(new_value).compact.map(&:to_i).sort
      existing_array = Array(existing_value).compact

      # Extraire les IDs de existing (peut être [{id: X}, {id: Y}] ou [X, Y])
      existing_ids = existing_array.map { |item| item.is_a?(Hash) ? item['id'] : item }.compact.map(&:to_i).sort

      new_array != existing_ids
    end

    # Compare phone_number : normalise en retirant espaces, tirets, points
    # Ex: "89 22 44 03" vs "89224403" → identiques après normalisation
    def values_differ_phone_number?(new_value, existing_value)
      return true if new_value.nil? != existing_value.nil?
      return false if new_value.nil?

      # Normaliser : retirer tous les caractères non-numériques (espaces, tirets, points, etc.)
      normalize_phone = ->(phone) { phone.to_s.gsub(/[^0-9+]/, '') }

      normalize_phone.call(new_value) != normalize_phone.call(existing_value)
    end

    def handle_api_error(error, dossier_number, data, existing_row, attempt)
      if attempt < @retry_attempts && retryable_error?(error)
        delay = @retry_delay * (2**(attempt - 1)) # Backoff exponentiel
        Rails.logger.warn "BaserowSync: Retry #{attempt}/#{@retry_attempts} après #{delay}s pour dossier #{dossier_number}: #{error.message}"
        sleep delay
        upsert_row_with_retry(dossier_number, data, existing_row, attempt + 1)
      else
        # Erreur finale
        Rails.logger.error "BaserowSync: Échec synchro dossier #{dossier_number} après #{attempt} tentatives: #{error.message}"
        Sentry.capture_exception(error, extra: { dossier: dossier_number, data: data, attempt: attempt })

        raise unless @options['continuer_si_erreur']

        false

      end
    end

    def retryable_error?(error)
      return false unless error.respond_to?(:status_code)

      RETRYABLE_STATUS_CODES.include?(error.status_code)
    end
  end
end
