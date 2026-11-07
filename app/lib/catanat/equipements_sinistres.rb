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
  class EquipementsSinistres < PertesRegroupees
    COLONNES = ["Catégorie d'équipement", 'Éléments', 'Montant déclaré (F)'].freeze
    RETENUS = ['Montant retenu (F)'].freeze

    def version
      super + 1
    end

    def required_fields
      super + %i[champs_source bloc_destination]
    end

    def authorized_fields
      super + %i[champ_categorie champ_montant]
    end

    private

    def champ_categorie = @params[:champ_categorie] || 'Catégorie'
    def champ_montant = @params[:champ_montant] || 'Montant du devis / facture de réparation ou remplacement (F)'

    def lignes = par_categorie(elements)

    def elements
      @params[:champs_source].to_h.flat_map do |bloc, gabarit|
        lignes_du_bloc(bloc.to_s).filter_map do |row|
          categorie = champ(row, champ_categorie)
          next if categorie.nil? || champ_value(categorie).blank?

          { categorie: champ_value(categorie), description: instanciate(gabarit.to_s, row).strip,
            montant: champ(row, champ_montant)&.int_value.to_i }
        end
      end
    end

    def par_categorie(elements)
      elements.group_by { it[:categorie] }.map do |categorie, liste|
        [categorie, liste.map { it[:description] }.compact_blank.join("\n"), liste.sum { it[:montant] }]
      end
    end
  end
end
