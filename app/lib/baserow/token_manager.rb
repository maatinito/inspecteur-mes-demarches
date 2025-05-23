# frozen_string_literal: true

module Baserow
  class TokenManager
    class << self
      # Durée de validité du cache en secondes (1 heure par défaut)
      CACHE_DURATION = 3600

      # Récupère le token correspondant à une configuration donnée
      def get_token(config_name)
        return default_token if config_name.blank?

        # Rechercher dans le cache
        cached_token = token_cache[config_name]
        return cached_token[:token] if cached_token && !cache_expired?(cached_token[:timestamp])

        # Si pas en cache ou cache expiré, récupérer et mettre en cache
        token = token_from_table(config_name) || default_token
        token_cache[config_name] = { token:, timestamp: Time.now.to_i }
        token
      end

      # Vide le cache des tokens
      def clear_cache
        @token_cache = nil
      end

      private

      # Cache des tokens par configuration
      def token_cache
        @token_cache ||= {}
      end

      # Vérifie si le cache est expiré
      def cache_expired?(timestamp)
        return true unless timestamp

        (Time.now.to_i - timestamp) > CACHE_DURATION
      end

      # Token par défaut (utilisé si aucune configuration spécifique n'est trouvée)
      def default_token
        ENV['BASEROW_API_TOKEN'] || raise('BASEROW_API_TOKEN environment variable is not set')
      end

      # Récupère le token depuis la table Baserow de tokens
      def token_from_table(config_name)
        # Vérifier si la table de tokens est configurée
        table_id = ENV.fetch('BASEROW_TOKEN_TABLE', nil)
        return nil unless table_id.present?

        # Créer un client avec le token par défaut pour accéder à la table de tokens
        client = Client.new(Config.base_url, default_token)

        begin
          # Récupérer les champs de la table
          fields = client.list_fields(table_id)

          # Identifier les champs "nom" et "token"
          name_field = fields.find { |f| f['name'].downcase =~ /nom|name|config/i }
          token_field = fields.find { |f| f['name'].downcase =~ /token|jeton|clé/i }

          return nil unless name_field && token_field

          # Construire le filtre pour rechercher la configuration
          params = {
            "filter__field_#{name_field['id']}__equal" => config_name.to_s
          }

          # Récupérer les enregistrements correspondants
          results = client.list_rows(table_id, params)

          # Retourner le token s'il est trouvé
          if (results['count']).positive?
            token = results['results'][0]["field_#{token_field['id']}"]
            return token if token.present?
          end

          nil
        rescue StandardError => e
          Rails.logger.error("Erreur lors de la récupération du token pour '#{config_name}': #{e.message}")
          nil
        end
      end
    end
  end
end
