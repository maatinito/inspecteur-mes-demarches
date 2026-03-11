# frozen_string_literal: true

module Grist
  class Config
    class << self
      def base_url
        (ENV['GRIST_URL'] || 'https://grist.mes-demarches.gov.pf').chomp('/')
      end

      def api_key(_config_name = nil)
        # Pour l'instant, une seule clé API. Extensible plus tard avec un TokenManager si nécessaire.
        ENV.fetch('GRIST_API_KEY')
      end

      def client(config_name = nil)
        Client.new(base_url, api_key(config_name))
      end

      def table(doc_id, table_id, config_name = nil)
        Table.new(client(config_name), doc_id, table_id)
      end
    end
  end
end
