# frozen_string_literal: true

module Excel
  class ExportRepetitions < FieldChecker
    def version
      super + 4
    end

    def required_fields
      super + %i[champ_cible modele]
    end

    def authorized_fields
      super + %i[champs_sources]
    end

    def initialize(params)
      super
      @champs_sources = Set.new(@params[:champs_sources] || [])
      @modele = @params[:modele]
      @champ_cible = @params[:champ_cible]
      raise "Modèle #{@modele} introuvable" unless File.exist?(@modele)
    end

    def process(demarche, dossier)
      super
      workbook = RubyXL::Parser.parse(@modele)
      dossier.champs.each do |champ|
        next unless champ.__typename == 'RepetitionChamp' && (@champs_sources.empty? || @champs_sources.include?(champ.label))

        worksheet = workbook[champ.label]
        champ.rows.each_with_index do |repetition, row_index|
          repetition.champs.each_with_index do |sous_champ, column_index|
            puts "#{row_index}, #{column_index}, #{sous_champ.value}"
          end
        end
        puts worksheet[0][0].value if worksheet.present?
      end
    end
  end
end
