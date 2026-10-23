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

    # Construit la référence de table attendue par `update_fields` /
    # `get_table_fields` / `field_exists?` à partir d'un id de table « nu »
    # (tel que stocké dans `main_table_external_id` / `backend_table_id`) et de
    # l'application.
    #
    # - Baserow : l'id nu suffit, on le renvoie tel quel.
    # - Grist   : ces méthodes exigent un id composite "doc_id:table_id".
    def table_ref(_application_id, table_id)
      table_id
    end

    # Fait afficher le numéro de dossier (et non l'id de ligne) dans la colonne
    # Dossier d'une table de bloc. Rien à faire par défaut : un link_row Baserow
    # affiche déjà la colonne primaire de la table liée.
    def show_dossier_number(_application_id, _table_id, _main_table_id); end

    # Rapproche un nom de table de son id : Grist dérive l'id du nom en gardant
    # la casse (« Rubriques concernées ICPE » → Rubriques_concernees_ICPE).
    def self.same_table_name?(name, other)
      name.to_s.parameterize(separator: '_') == other.to_s.parameterize(separator: '_')
    end

    def table_exists?(_application_id, _name)
      raise NotImplementedError
    end

    def field_exists?(_table_id, _name)
      raise NotImplementedError
    end
  end
end
