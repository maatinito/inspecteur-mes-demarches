# frozen_string_literal: true

module Catanat
  # Prépare l'indemnisation des cultures sinistrées (DAG, déclaration de
  # sinistre CATANAT) à partir du bloc du formulaire où l'agriculteur déclare
  # une ligne par culture (culture, bio, surface détruite) :
  #
  # - bloc_indemnisation : une ligne par famille de cultures et par mode
  #   (bio / non bio) : Famille de cultures, Cultures, Bio / non bio,
  #   m² déclarés. Les m² retenus saisis par l'instructeur et les formules du
  #   barème ne sont pas touchés ;
  # - bloc_plafond : une ligne par famille avec le total des montants
  #   théoriques calculés par les formules, que les formules du bloc plafonnent.
  #   Les formules ne savent pas sommer par famille (pas de SOMME.SI).
  #
  # La famille vient de la colonne « famille » du référentiel de la liste des
  # cultures, que l'API expose pour une liste à choix unique. Si `familles`
  # (les options des listes Famille des annotations) est donné, elle est ramenée
  # à l'option qui ne diffère que par les accents ou la ponctuation.
  #
  # Si `champ_surfaces` est donné, cette annotation texte reçoit le total des
  # surfaces déclarées : « 6000 m² dont 500 m² en bio ».
  class CulturesSinistrees < FieldChecker
    include EcritureBloc

    REFERENTIEL_COLUMN_ID = /\.referentiel\.data\.row\.(\w+)\z/
    INDEMNISATION = ['Famille de cultures', 'Cultures', 'Bio / non bio', 'm² déclarés'].freeze
    MONTANT = 'Montant théorique (F)'
    RETENUS = 'm² retenus'
    PLAFOND = ['Famille (récapitulatif)', 'Montant théorique total (F)'].freeze

    def version
      super + 2
    end

    def required_fields
      super + %i[champ bloc_indemnisation bloc_plafond]
    end

    def authorized_fields
      super + %i[champ_culture champ_bio champ_surface champ_surfaces familles]
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      cultures = declarations
      groupes = par_famille_et_mode(cultures)
      montants = montants_actuels
      changed = recopie(@params[:bloc_indemnisation], groupes.map { |g| g.values_at(:famille, :cultures, :mode, :surface) },
                        INDEMNISATION) { |row| avertir_ligne_retiree(row) }
      changed |= recopie(@params[:bloc_plafond], plafonds(groupes, montants), PLAFOND)
      changed |= ecrit_surfaces(cultures) if @params[:champ_surfaces].present?
      dossier_updated(@dossier) if changed
    end

    private

    def champ_culture = @params[:champ_culture] || 'Culture'
    def champ_bio = @params[:champ_bio] || 'Culture bio ?'
    def champ_surface = @params[:champ_surface] || 'Surface détruite (m²)'

    def declarations
      lignes_du_bloc(@params[:champ]).filter_map do |row|
        culture = row.champs.find { |c| c.label == champ_culture }
        next if culture&.string_value.blank?

        {
          culture: culture.string_value,
          famille: famille(culture),
          mode: row.champs.find { |c| c.label == champ_bio }&.checked ? 'Bio' : 'Non bio',
          surface: row.champs.find { |c| c.label == champ_surface }&.int_value.to_i
        }
      end
    end

    def famille(champ)
      return '' unless champ.respond_to?(:columns) && champ.columns

      column = champ.columns.find { |c| Base64.decode64(c.id)[REFERENTIEL_COLUMN_ID, 1]&.casecmp?('famille') }
      option_equivalente(column&.string_value.to_s, @params[:familles])
    end

    def par_famille_et_mode(cultures)
      cultures.group_by { |c| [c[:famille], c[:mode]] }.map do |(famille, mode), lignes|
        { famille:, mode:, cultures: lignes.map { it[:culture] }.uniq.join(', '), surface: lignes.sum { it[:surface] } }
      end
    end

    # Montants théoriques déjà calculés par les formules, par [famille, mode].
    def montants_actuels
      rows = SetAnnotationValue.get_annotation(@dossier, @params[:bloc_indemnisation])&.rows
      Array(rows).each_with_object(Hash.new(0)) do |row, montants|
        montants[[valeur(row, INDEMNISATION[0]), valeur(row, INDEMNISATION[2])]] += valeur(row, MONTANT).to_f.round
      end
    end

    def plafonds(groupes, montants)
      groupes.group_by { it[:famille] }.map do |famille, liste|
        [famille, liste.sum { |g| montants[[g[:famille], g[:mode]]] }]
      end
    end

    def ecrit_surfaces(cultures)
      total = cultures.sum { it[:surface] }
      bio = cultures.select { it[:mode] == 'Bio' }.sum { it[:surface] }
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, @params[:champ_surfaces], "#{total} m² dont #{bio} m² en bio")
    end

    def avertir_ligne_retiree(row)
      return unless valeur(row, RETENUS).to_i.positive?

      Rails.logger.warn("Dossier #{@dossier.number} : une ligne de '#{@params[:bloc_indemnisation]}' n'a plus de culture déclarée mais garde des m² retenus")
    end
  end
end
