# frozen_string_literal: true

require_relative 'column_descriptor'

module Excel
  # Lecture d'une feuille d'un classeur xlsx, indépendante de Mes-Démarches et
  # de Grist.
  #
  # Extraite de GetSheets pour être partageable avec le plugin ExcelVersGrist :
  # GetSheets vit dans un modèle pipeline (process_row/output) consommé par
  # Partition/Group, qui ne convient pas à un FieldChecker « par dossier ».
  #
  # `feuille` : Integer (position 1-based), String (nom), nil (première feuille).
  # `ligne_entete` : forçage 1-based de la ligne d'en-tête. La détection
  # automatique est basique — volontairement, cf. spec §2 — et se trompe quand
  # l'en-tête porte un trou : ce paramètre est la porte de sortie.
  class SheetReader
    class FeuilleIntrouvable < StandardError; end

    # Ponctuation retirée des en-têtes. Apostrophes (droite et typographique),
    # traits d'union et signe degré sont volontairement conservés : ils portent
    # du sens dans les libellés français, qui servent aussi de noms de colonnes
    # cibles (« Numéro d'arrêté », « N° TAHITI », « Sous-total »).
    PONCTUATION = %r{[(){}\[\]/\\,;:!?"*%#&@|<>=+~^$`.]}

    # DateTime et Time avant Date : en Ruby, DateTime hérite de Date.
    CLASSES_TYPES = [
      [TrueClass, 'Bool'], [FalseClass, 'Bool'],
      [Float, 'Numeric'], [Integer, 'Int'],
      [DateTime, 'DateTime:UTC'], [Time, 'DateTime:UTC'], [Date, 'Date']
    ].freeze

    attr_reader :ligne_entete

    # Type Grist déduit des classes Ruby renvoyées par roo. Une colonne mixte ou
    # vide donne Text : on ne perd jamais de donnée à l'inférence, et un type
    # précis peut toujours être forcé par le mapping de la configuration.
    def self.inferer_type(valeurs)
      types = valeurs.compact.map { |v| type_de(v) }.uniq
      return 'Text' if types.size != 1

      types.first
    end

    def self.type_de(valeur)
      CLASSES_TYPES.each { |klass, type| return type if valeur.is_a?(klass) }
      'Text'
    end

    TYPES_NUMERIQUES = %w[Numeric Int].freeze
    # Espaces à retirer d'un nombre saisi à la main. Les insécables sont écrites
    # en échappement : un caractère invisible dans la source se ferait effacer au
    # premier reformatage (U+00A0 insécable, U+202F insécable fine).
    ESPACES = /[[:space:]\u00A0\u202F]/

    # Coerce une valeur vers un type numérique cible.
    #
    # Les colonnes « numériques » des formulaires réels contiennent souvent du
    # texte saisi à la main (« 1 010,50 ») : roo renvoie alors une String. On
    # coerce plutôt que de perdre la valeur — vérifié sur les fichiers de la
    # démarche 1536. Une valeur non convertible donne nil, jamais zéro : un zéro
    # serait un faux chiffre injecté dans les calculs en aval.
    def self.coercer(valeur, type)
      return valeur unless TYPES_NUMERIQUES.include?(type)
      return valeur if valeur.is_a?(Numeric)
      return nil if valeur.nil?

      nettoye = valeur.to_s.gsub(ESPACES, '').tr(',', '.')
      nombre = nettoye.empty? ? nil : Float(nettoye, exception: false)
      return nil if nombre.nil?

      type == 'Int' ? nombre.to_i : nombre
    end

    # Nettoie les en-têtes et garantit des noms non vides et distincts : deux
    # colonnes source qui porteraient le même nom écriraient dans la même cible.
    def self.sanitize_noms(entetes)
      vus = Hash.new(0)
      entetes.each_with_index.map do |brut, index|
        base = brut.to_s.gsub(/[\r\n]+/, ' ').gsub(PONCTUATION, ' ').squeeze(' ').strip
        base = "Colonne_#{index + 1}" if base.empty?
        vus[base] += 1
        vus[base] > 1 ? "#{base}_#{vus[base]}" : base
      end
    end

    # Noms des feuilles d'un classeur, dans l'ordre du document.
    def self.noms_feuilles(chemin)
      xlsx = Roo::Spreadsheet.open(chemin)
      xlsx.sheets
    ensure
      xlsx&.close
    end

    def initialize(chemin, feuille: nil, ligne_entete: nil)
      @xlsx = Roo::Spreadsheet.open(chemin)
      @sheet = selectionner_feuille(feuille)
      @ligne_entete = ligne_entete || detecter_ligne_entete(@sheet)
    end

    def nom_feuille
      @sheet.default_sheet
    end

    def colonnes
      @colonnes ||= construire_colonnes
    end

    # Lignes de données, clés = noms de colonnes sanitizés.
    #
    # Les valeurs sont rendues telles que roo les lit, sans coercition : celle-ci
    # dépend du type de la colonne *cible*, que seul l'appelant connaît. Voir
    # .coercer, à appliquer avec le type cible du mapping.
    def lignes
      @lignes ||= construire_lignes
    end

    def close
      @xlsx&.close
    end

    private

    def selectionner_feuille(feuille)
      noms = @xlsx.sheets
      nom = case feuille
            when nil then noms.first
            when Integer then noms[feuille - 1]
            else noms.find { |n| n == feuille }
            end
      raise FeuilleIntrouvable, "Feuille #{feuille.inspect} introuvable (disponibles : #{noms.join(', ')})" if nom.nil?

      @xlsx.sheet(nom)
    end

    # Heuristique reprise de GetSheets : la ligne d'en-tête est celle qui porte
    # le plus de cellules remplies consécutives.
    def detecter_ligne_entete(sheet)
      ligne = 0
      max = 0
      sheet.each_row_streaming do |row|
        cell = row.find { |c| c.value.nil? } || row.last
        next if cell.nil?

        count = cell.coordinate[1]
        count -= 1 if cell.value.nil?
        if count > max
          max = count
          ligne = cell.coordinate[0]
        end
      end
      ligne
    end

    def entetes_bruts
      @entetes_bruts ||= @ligne_entete.positive? ? @sheet.row(@ligne_entete) : []
    end

    # Valeurs des lignes de données, indexées par position de colonne.
    #
    # Un seul balayage sert à la fois à l'inférence de type et à la construction
    # des lignes : ligne_de_donnees? ne dépendant pas de `colonnes`, il n'y a pas
    # de récursion entre les deux.
    def lignes_brutes
      @lignes_brutes ||= begin
        largeur = entetes_bruts.size
        resultat = []
        @sheet.each_row_streaming do |row|
          next unless ligne_de_donnees?(row)

          resultat << Array.new(largeur) { |index| row[index]&.value }
        end
        resultat
      end
    end

    def construire_colonnes
      noms = self.class.sanitize_noms(entetes_bruts)
      entetes_bruts.each_with_index.map do |brut, index|
        valeurs = lignes_brutes.map { |ligne| ligne[index] }
        ColumnDescriptor.new(nom: noms[index], en_tete_brut: brut, index: index,
                             type_infere: self.class.inferer_type(valeurs))
      end
    end

    def construire_lignes
      lignes_brutes.map do |ligne|
        colonnes.to_h { |col| [col.nom, ligne[col.index]] }
      end
    end

    # Une ligne porte des données si elle est postérieure à l'en-tête et non
    # vide. GetSheets testait row[1] — la *deuxième* cellule — ce qui écartait à
    # tort toute ligne dont la 2e colonne était vide.
    def ligne_de_donnees?(row)
      return false if row.blank?
      return false unless row.first.coordinate[0] > @ligne_entete

      row.any? { |cell| cell.value.present? }
    end
  end
end
