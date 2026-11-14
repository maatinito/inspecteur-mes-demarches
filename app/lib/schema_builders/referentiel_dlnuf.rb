# frozen_string_literal: true

module SchemaBuilders
  # Type de référentiel d'une table Baserow (archive ou DLNUF) vu depuis le builder.
  #
  # Le builder tourne parfois sur un autre robot (dev, staging) que celui qui synchronise
  # (production) : il décide d'après le marqueur lu sur la table, jamais d'après sa propre base,
  # et n'écrit jamais dans `referentiel_tables`. Seul `retablir!` lit `ReferentielTable`, pour
  # restaurer le type figé par le robot sur lequel il s'exécute.
  class ReferentielDlnuf
    TYPES = { archive: :archive, dlnuf: :dlnuf }.freeze
    NOM_PROPRIETAIRE = MetadataFields.system.find { |champ| champ.key == :email_usager }.name

    def initialize(client:)
      @client = client
    end

    # :archive | :dlnuf | :invalid, d'après le marqueur de la colonne primaire.
    def type_lu(table_id)
      lu = Referentiel::Marqueur.type_table(primaire(colonnes(table_id))&.dig('description'))
      lu == :invalid ? :invalid : TYPES.fetch(lu.first)
    end

    def colonnes_fichier(table_id)
      colonnes(table_id).select { |colonne| colonne['type'] == 'file' }.map { |colonne| colonne['name'] }
    end

    # Application (database) qui porte la table, lue sur Baserow plutôt que dans la cible, dont
    # l'identifiant peut être périmé.
    def application_de(table_id)
      @client.get_table(table_id)['database_id']
    end

    # Tables de l'application, autres que la principale, dont la colonne « Dossier » est un link_row
    # vers la table principale : même critère que la synchronisation. Toute autre table est étrangère.
    def tables_liees(application_id, table_id)
      principale = table_id.to_i
      Array(@client.list_tables(application_id)).filter_map do |table|
        id = table['id'].to_i
        next if id == principale

        dossier = colonnes(id).find { |colonne| colonne['name'] == 'Dossier' }
        id if dossier && dossier['type'] == 'link_row' && dossier['link_row_table_id'].to_i == principale
      end
    end

    # Pose le marqueur sur une table neuve, ou vérifie celui d'une table existante.
    # Rend l'identifiant de la colonne propriétaire.
    def finaliser!(table_id, creee:)
      champs = colonnes(table_id)
      primaire = primaire(champs)
      proprietaire = champs.find { |colonne| colonne['name'] == NOM_PROPRIETAIRE }
      refuser!("colonne « #{NOM_PROPRIETAIRE} » absente de la table #{table_id}") unless proprietaire && primaire

      lu = Referentiel::Marqueur.type_table(primaire['description'])
      return proprietaire['id'] if lu == [:dlnuf, proprietaire['id']]

      refuser!("table #{table_id} existante sans marqueur DLNUF concordant") unless creee && lu == [:archive, nil]

      @client.update_field(primaire['id'], description: Referentiel::Marqueur.description_table(
        mode: :dlnuf, proprietaire: proprietaire['id'], existante: primaire['description']
      ))
      proprietaire['id']
    end

    # Réécrit le marqueur d'après l'enregistrement de CE robot.
    def retablir!(table_id)
      table = ReferentielTable.find_by(backend: 'baserow', table_ref: table_id.to_s)
      refuser!("table #{table_id} inconnue de ce robot : rien à rétablir") unless table

      primaire = primaire(colonnes(table_id))
      refuser!("table #{table_id} sans colonne primaire") unless primaire

      @client.update_field(primaire['id'], description: Referentiel::Marqueur.description_table(
        mode: table.mode.to_sym, proprietaire: table.proprietaire, existante: primaire['description']
      ))
      table
    end

    private

    def colonnes(table_id)
      Array(@client.get_table_fields(table_id))
    end

    def primaire(champs)
      champs.find { |colonne| colonne['primary'] }
    end

    def refuser!(message)
      raise Referentiel::Verrou::Refus, message
    end
  end
end
