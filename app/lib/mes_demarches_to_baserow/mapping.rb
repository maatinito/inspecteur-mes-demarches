# frozen_string_literal: true

module MesDemarchesToBaserow
  # Bloc `mapping:` de baserow_sync : colonne de la table cible => valeur.
  # - Integer : stable_id d'un champ usager (valeur typée native) ;
  # - String  : gabarit instancié par FieldChecker#instanciate (sans accolade = constante).
  #
  # Construit une fois par passe : confronte la configuration à la table Baserow et aux
  # révisions de la démarche. Garde-fous non destructifs : une entrée douteuse est écartée
  # (colonne jamais écrite) et décrite dans #avertissements, rien n'est bloqué.
  class Mapping
    Entree = Struct.new(:colonne, :stable_id, :gabarit)

    TYPES_GABARIT = %w[text long_text single_select email url].freeze

    # Champs que la synchro ne sait jamais écrire : les désigner viderait la colonne à chaque dossier.
    TYPES_NON_INSCRIPTIBLES = %w[RepetitionChampDescriptor TitreIdentiteChampDescriptor
                                 HeaderSectionChampDescriptor ExplicationChampDescriptor].freeze

    # Mêmes découpages que FieldChecker#instanciate_once : ternaires d'abord, puis {préfixe;Champ;suffixe}.
    TERNAIRE = /{([^{}]+\?[^{}]+:[^{}]+)}/
    PLACEHOLDER = /{(?:([^{};]*);)?([^{}]+?)(?:;([^{};]*))?}/

    # Attribut ou chemin du dossier ({number}, {demandeur.nom}) : résolu par instanciate, non contrôlé.
    ATTRIBUT_DOSSIER = /\A[a-z_][a-z0-9_.]*\z/

    attr_reader :entrees, :avertissements

    # @return [Array<String>] erreurs bloquantes de forme (chargement de la configuration)
    def self.erreurs_de_config(config)
      return ['mapping doit être une table « colonne: valeur »'] unless config.is_a?(Hash)

      config.reject { |_colonne, valeur| valeur.is_a?(Integer) || valeur.is_a?(String) }.map do |colonne, valeur|
        "mapping de « #{colonne} » : #{valeur.inspect} n'est ni un stable_id (entier) ni un gabarit (texte)"
      end
    end

    # @param champs [Hash{Integer => String}] stable_id => libellé des champs usager (révisions)
    # @param annotations [Hash{Integer => String}] idem pour les annotations privées
    # @param types [Hash{Integer => String}] stable_id => __typename du descripteur de champ
    def initialize(config, field_metadata:, champs:, annotations:, types: {})
      @field_metadata = field_metadata
      @champs = champs
      @types = types
      @annotations = annotations
      @libelles = (champs.values + annotations.values).to_set
      @avertissements = []
      @entrees = config.filter_map { |colonne, valeur| entree(colonne.to_s, valeur) }
    end

    private

    def entree(colonne, valeur)
      meta = @field_metadata[colonne]
      return avertir("colonne « #{colonne} » absente de la table, ignorée") unless meta

      valeur.is_a?(Integer) ? entree_stable_id(colonne, valeur) : entree_gabarit(colonne, valeur, meta['type'])
    end

    def entree_stable_id(colonne, stable_id)
      return avertir("colonne « #{colonne} » : #{stable_id} est un champ #{@types[stable_id]}, jamais synchronisé, ignorée") if TYPES_NON_INSCRIPTIBLES.include?(@types[stable_id])
      return Entree.new(colonne, stable_id, nil) if @champs.key?(stable_id)

      if @annotations.key?(stable_id)
        avertir("colonne « #{colonne} » : #{stable_id} est une annotation privée (le socle ne reprend que les champs usager), ignorée")
      else
        avertir("colonne « #{colonne} » : stable_id #{stable_id} inconnu de la démarche, ignorée")
      end
    end

    def entree_gabarit(colonne, gabarit, type)
      return avertir("colonne « #{colonne} » de type #{type} : un gabarit n'y est pas admis (stable_id attendu), ignorée") unless TYPES_GABARIT.include?(type)

      inconnus = libelles(gabarit).reject { |libelle| libelle_connu?(libelle) }
      return avertir("colonne « #{colonne} » : libellé(s) #{inconnus.join(', ')} inconnu(s) de la démarche, ignorée") if inconnus.any?

      avertir("colonne « #{colonne} » : « #{gabarit} » écrit comme constante — stable_id attendu ? (sans guillemets)") if gabarit.match?(/\A\d+\z/)
      Entree.new(colonne, nil, gabarit)
    end

    # Noms référencés, lus comme instanciate : la condition d'un ternaire valide (« ? » avant
    # le dernier « : »), puis les autres {…} une fois les ternaires retirés.
    def libelles(gabarit)
      conditions = []
      reste = gabarit.gsub(TERNAIRE) do |brut|
        expression = Regexp.last_match(1)
        question = expression.index('?')
        next brut unless question < expression.rindex(':')

        conditions << expression[0...question].strip
        ''
      end
      conditions + reste.scan(PLACEHOLDER).map { |_prefixe, nom, _suffixe| nom.strip }
    end

    # Libellé exact, racine d'un chemin pointé ({N° Tahiti.adresse}), ou attribut du dossier.
    def libelle_connu?(nom)
      @libelles.include?(nom) || @libelles.include?(nom.split('.').first.strip) || nom.match?(ATTRIBUT_DOSSIER)
    end

    def avertir(message)
      @avertissements << message
      nil
    end
  end
end
