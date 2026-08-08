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

    attr_reader :ligne_entete

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

    def construire_colonnes
      entetes_bruts.each_with_index.map do |brut, index|
        ColumnDescriptor.new(nom: brut.to_s.strip, en_tete_brut: brut, index: index, type_infere: 'Text')
      end
    end

    def construire_lignes
      resultat = []
      @sheet.each_row_streaming do |row|
        next unless ligne_de_donnees?(row)

        resultat << colonnes.to_h do |col|
          [col.nom, row[col.index]&.value]
        end
      end
      resultat
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
