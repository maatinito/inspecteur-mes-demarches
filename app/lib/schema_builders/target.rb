# frozen_string_literal: true

module SchemaBuilders
  # Interface (mixin) que doivent implémenter les adapters de cibles
  # (Baserow, Grist, etc.) pour le builder de schémas.
  #
  # Chaque méthode de base lève NotImplementedError. Les adapters
  # concrets délèguent à leurs clients respectifs.
  module Target
    def list_workspaces
      raise NotImplementedError
    end

    def list_applications(_workspace_id)
      raise NotImplementedError
    end

    def list_tables(_application_id)
      raise NotImplementedError
    end

    def create_table(_application_id, _name, _fields)
      raise NotImplementedError
    end

    def update_fields(_table_id, _fields)
      raise NotImplementedError
    end

    def table_exists?(_application_id, _name)
      raise NotImplementedError
    end

    def field_exists?(_table_id, _name)
      raise NotImplementedError
    end
  end
end
