# frozen_string_literal: true

require_relative 'sheet_reader'

module Excel
  class GetSheets < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[champ]
    end

    def authorized_fields
      super + %i[feuille ligne_entete]
    end

    # La lecture est déléguée à Excel::SheetReader, partagé avec ExcelVersGrist.
    #
    # Le contrat est inchangé : toutes les feuilles sont exposées, une entrée de
    # sortie par feuille (un modèle de publipostage peut rendre un tableau par
    # feuille). `feuille` restreint facultativement à une seule feuille ; c'est
    # le plugin ExcelVersGrist, lui, qui prend la première feuille par défaut.
    def process_row(row, output)
      champs = object_field_values(row, params[:champ])
      champs.each do |champ_source|
        raise "Le champ #{params[:champ]} n'est pas de type PieceJustificative" if champ_source.__typename != 'PieceJustificativeChamp'

        source_file = champ_source.files.filter { File.extname(it.filename) == '.xlsx' }.last
        next unless source_file

        PieceJustificativeCache.get(source_file) do |file|
          feuilles_a_lire(file).each do |nom|
            reader = Excel::SheetReader.new(file, feuille: nom, ligne_entete: params[:ligne_entete])
            output["#{params[:champ]}.#{nom}"] = reader.lignes
          ensure
            reader&.close
          end
        end
      end
      output
    end

    def feuilles_a_lire(file)
      params[:feuille] ? [params[:feuille]] : Excel::SheetReader.noms_feuilles(file)
    end
  end
end
