# frozen_string_literal: true

module Catanat
  # Regroupe par catégorie du barème les équipements et bâtiments endommagés
  # déclarés dans un ou plusieurs blocs du formulaire et les recopie dans un
  # bloc d'annotations, une ligne par catégorie : Catégorie d'équipement,
  # Éléments (description de chaque élément), Montant déclaré (F) (somme des
  # devis / factures). Le montant retenu saisi par l'instructeur et les
  # formules de plafond ne sont pas touchés.
  #
  # Paramètres :
  #   champs_source : bloc source => gabarit de description d'un élément, ex.
  #     { "Moyen matériel endommagé": "{Matériel agricole}{ (;Référence et caractéristique;)}" }
  #   bloc_destination : bloc d'annotations
  # Paramètres facultatifs :
  #   champ_categorie : liste de la catégorie dans les blocs source (défaut « Catégorie »)
  #   champ_montant : montant du devis / facture dans les blocs source
  class EquipementsSinistres < FieldChecker
    include EcritureBloc

    COLONNES = ["Catégorie d'équipement", 'Éléments', 'Montant déclaré (F)'].freeze
    RETENU = 'Montant retenu (F)'

    def version
      super + 1
    end

    def required_fields
      super + %i[champs_source bloc_destination]
    end

    def authorized_fields
      super + %i[champ_categorie champ_montant]
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      changed = recopie(@params[:bloc_destination], par_categorie(elements), COLONNES) { |row| avertir_ligne_retiree(row) }
      dossier_updated(@dossier) if changed
    end

    private

    def champ_categorie = @params[:champ_categorie] || 'Catégorie'
    def champ_montant = @params[:champ_montant] || 'Montant du devis / facture de réparation ou remplacement (F)'

    def elements
      @params[:champs_source].to_h.flat_map do |bloc, gabarit|
        lignes_du_bloc(bloc.to_s).filter_map do |row|
          categorie = row.champs.find { |c| c.label == champ_categorie }
          next if categorie.nil? || champ_value(categorie).blank?

          { categorie: champ_value(categorie), description: instanciate(gabarit.to_s, row).strip,
            montant: row.champs.find { |c| c.label == champ_montant }&.int_value.to_i }
        end
      end
    end

    def par_categorie(elements)
      elements.group_by { it[:categorie] }.map do |categorie, liste|
        [categorie, liste.map { it[:description] }.compact_blank.join("\n"), liste.sum { it[:montant] }]
      end
    end

    def avertir_ligne_retiree(row)
      return unless valeur(row, RETENU).to_i.positive?

      Rails.logger.warn("Dossier #{@dossier.number} : une ligne de '#{@params[:bloc_destination]}' n'a plus d'élément déclaré mais garde un montant retenu")
    end
  end
end
