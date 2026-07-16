# frozen_string_literal: true

module SchemaBuilders
  # Source UNIQUE des colonnes de métadonnées (système + identité demandeur)
  # ajoutées à la table principale. Consommée à la fois par :
  #   - SchemaBuilders::MainTableBuilder / Differ  (création + diff des colonnes)
  #   - MesDemarchesToGrist / MesDemarchesToBaserow data_extractors (valeurs)
  #
  # Le contrat builder <-> synchro est par LIBELLÉ de colonne : un nom unique et
  # accentué partout garantit zéro divergence entre plateformes.
  #
  # Chaque Field porte :
  #   - name     : libellé de colonne (identique Grist/Baserow)
  #   - typename : type Mes-Démarches (le TypeMapper produit le type natif cible)
  #   - options  : options éventuelles (choix du Statut)
  #   - source   : extraction de la valeur depuis un dossier (utilisé par les
  #                data_extractors ; ignoré par le builder)
  module MetadataFields
    # Valeurs brutes de l'état d'un dossier (dossier.state).
    ETAT_CHOICES = %w[en_construction en_instruction accepte refuse sans_suite].freeze

    Field = Struct.new(:key, :name, :typename, :options, :source) do
      def datetime? = typename == 'DatetimeChampDescriptor'
      def multiple? = typename == 'MultipleDropDownListChampDescriptor'
      def primary? = key == :dossier
    end

    DEMANDEUR_DEFS = {
      physique: [
        { key: :civilite, name: 'Civilité', src: ->(d) { d.demandeur&.civilite } },
        { key: :nom, name: 'Nom', src: ->(d) { d.demandeur&.nom } },
        { key: :prenom, name: 'Prénom', src: ->(d) { d.demandeur&.prenom } }
      ],
      morale: [
        { key: :numero_tahiti, name: 'Numéro TAHITI', src: ->(d) { d.demandeur&.siret } },
        { key: :raison_sociale, name: 'Raison sociale', src: ->(d) { d.demandeur&.entreprise&.raison_sociale } },
        { key: :nom_commercial, name: 'Nom commercial', src: ->(d) { d.demandeur&.entreprise&.nom_commercial } },
        { key: :forme_juridique, name: 'Forme juridique', src: ->(d) { d.demandeur&.entreprise&.forme_juridique } },
        { key: :libelle_naf, name: 'Libellé NAF', src: ->(d) { d.demandeur&.libelle_naf } }
      ]
    }.freeze

    module_function

    # Colonne primaire (numéro de dossier).
    def dossier
      Field.new(key: :dossier, name: 'Dossier', typename: 'IntegerNumberChampDescriptor',
                source: lambda(&:number))
    end

    # Champs système toujours présents (hors demandeur).
    def system
      [
        Field.new(key: :statut, name: 'Statut', typename: 'DropDownListChampDescriptor',
                  options: ETAT_CHOICES, source: lambda(&:state)),
        Field.new(key: :date_depot, name: 'Date de dépôt', typename: 'DatetimeChampDescriptor',
                  source: lambda(&:date_depot)),
        Field.new(key: :date_passage, name: 'Date de passage en instruction', typename: 'DatetimeChampDescriptor',
                  source: lambda(&:date_passage_en_instruction)),
        Field.new(key: :date_traitement, name: 'Date de traitement', typename: 'DatetimeChampDescriptor',
                  source: lambda(&:date_traitement)),
        Field.new(key: :email_usager, name: 'Email usager', typename: 'EmailChampDescriptor',
                  source: ->(d) { d.usager&.email }),
        Field.new(key: :groupe_instructeur, name: 'Groupe instructeur', typename: 'TextChampDescriptor',
                  source: ->(d) { d.groupe_instructeur&.label }),
        Field.new(key: :labels, name: 'Labels', typename: 'MultipleDropDownListChampDescriptor',
                  source: ->(d) { (d.respond_to?(:labels) && d.labels) || [] })
      ]
    end

    # Champs d'identité du demandeur pour un mode donné (:physique ou :morale).
    def demandeur(mode)
      Array(DEMANDEUR_DEFS[mode&.to_sym]).map do |h|
        Field.new(key: h[:key], name: h[:name], typename: 'TextChampDescriptor', source: h[:src])
      end
    end

    # Toutes les colonnes de métadonnées pour des modes demandeur donnés.
    # `modes` : Array de :physique / :morale (souvent un seul ; les deux en repli).
    def all(modes)
      [dossier] + system + Array(modes).uniq.flat_map { |m| demandeur(m) }
    end

    # Déduit le mode demandeur (:physique / :morale) depuis le __typename d'un
    # demandeur de dossier. nil si inconnu/absent.
    def mode_for_typename(typename)
      case typename.to_s
      when 'PersonnePhysique' then :physique
      when 'PersonneMorale', 'PersonneMoraleIncomplete' then :morale
      end
    end
  end
end
