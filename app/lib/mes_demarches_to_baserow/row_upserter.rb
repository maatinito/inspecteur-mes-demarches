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

    def initialize(table, options = {})
      @table = table
      @options = options
      @retry_attempts = options['tentatives'] || 3
      @retry_delay = options['delai_retry'] || 5
    end

    def upsert_row(dossier_number, data)
      upsert_row_with_retry(dossier_number, data)
    end

    private

    def upsert_row_with_retry(dossier_number, data, attempt = 1)
      existing_row = find_existing_row(dossier_number)

      if existing_row
        @table.update_row(existing_row['id'], data)
        Rails.logger.info "BaserowSync: Row mise à jour (dossier #{dossier_number}, row_id #{existing_row['id']})"
      else
        # S'assurer que le champ Dossier est présent
        data_with_dossier = data.merge('Dossier' => dossier_number)
        new_row = @table.create_row(data_with_dossier)
        Rails.logger.info "BaserowSync: Row créée (dossier #{dossier_number}, row_id #{new_row['id']})"
      end

      true
    rescue Baserow::APIError => e
      handle_api_error(e, dossier_number, data, attempt)
    end

    def find_existing_row(dossier_number)
      # Chercher par champ "Dossier"
      results = @table.search('Dossier', dossier_number.to_s)
      results.first
    rescue StandardError => e
      Rails.logger.warn "BaserowSync: Erreur recherche row (dossier #{dossier_number}): #{e.message}"
      nil
    end

    def handle_api_error(error, dossier_number, data, attempt)
      if attempt < @retry_attempts && retryable_error?(error)
        delay = @retry_delay * (2**(attempt - 1)) # Backoff exponentiel
        Rails.logger.warn "BaserowSync: Retry #{attempt}/#{@retry_attempts} après #{delay}s pour dossier #{dossier_number}: #{error.message}"
        sleep delay
        upsert_row_with_retry(dossier_number, data, attempt + 1)
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
