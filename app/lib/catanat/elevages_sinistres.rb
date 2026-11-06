# frozen_string_literal: true

module Catanat
  # Regroupe par type d'animal les pertes d'élevage déclarées (une ligne par
  # élevage sinistré) et les recopie dans un bloc d'annotations, une ligne par
  # type : Catégorie d'animaux, Animaux déclarés non bio, Animaux déclarés bio.
  # Le barème bio de l'annexe 2/4 diffère selon le type (pas de majoration
  # uniforme) : bio et non bio restent sur la même ligne, que le plafond
  # couvre entière. Les animaux retenus saisis par l'instructeur et les
  # formules ne sont pas touchés.
  class ElevagesSinistres < FieldChecker
    include EcritureBloc

    COLONNES = ["Catégorie d'animaux", 'Animaux déclarés non bio', 'Animaux déclarés bio'].freeze
    RETENUS = ['Animaux retenus non bio', 'Animaux retenus bio'].freeze

    def version
      super + 1
    end

    def required_fields
      super + %i[champ bloc_destination]
    end

    def authorized_fields
      super + %i[champ_type champ_bio champ_nombre]
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      changed = recopie(@params[:bloc_destination], par_type(pertes), COLONNES) { |row| avertir_ligne_retiree(row) }
      dossier_updated(@dossier) if changed
    end

    private

    def champ_type = @params[:champ_type] || "Type d'élevage"
    def champ_bio = @params[:champ_bio] || 'Élevage bio ?'
    def champ_nombre = @params[:champ_nombre] || "Nombre d'animaux perdus"

    def pertes
      lignes_du_bloc(@params[:champ]).filter_map do |row|
        type = row.champs.find { |c| c.label == champ_type }
        next if type.nil? || champ_value(type).blank?

        { type: champ_value(type), bio: row.champs.find { |c| c.label == champ_bio }&.checked,
          nombre: row.champs.find { |c| c.label == champ_nombre }&.int_value.to_i }
      end
    end

    def par_type(pertes)
      pertes.group_by { it[:type] }.map do |type, liste|
        bio, non_bio = liste.partition { it[:bio] }
        [type, non_bio.sum { it[:nombre] }, bio.sum { it[:nombre] }]
      end
    end

    def avertir_ligne_retiree(row)
      return unless RETENUS.any? { |label| valeur(row, label).to_i.positive? }

      Rails.logger.warn("Dossier #{@dossier.number} : une ligne de '#{@params[:bloc_destination]}' n'a plus d'élevage déclaré mais garde des animaux retenus")
    end
  end
end
