# frozen_string_literal: true

module Baserow
  class Config
    class << self
      def base_url
        ENV['BASEROW_URL'] || 'https://api-baserow.mes-demarches.gov.pf'
      end

      def api_token(config_name = nil)
        TokenManager.get_token(config_name)
      end

      def client(config_name = nil)
        # Ne pas mettre en cache le client pour permettre d'utiliser différents tokens
        Client.new(base_url, api_token(config_name))
      end

      def table(table_id, config_name = nil, table_name = nil)
        Table.new(client(config_name), table_id, table_name)
      end
    end
  end
end
