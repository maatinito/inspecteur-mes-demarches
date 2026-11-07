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
  class CulturesSinistrees < PertesRegroupees
    REFERENTIEL_COLUMN_ID = /\.referentiel\.data\.row\.(\w+)\z/
    COLONNES = ['Famille de cultures', 'Cultures', 'Bio / non bio', 'm² déclarés'].freeze
    RETENUS = ['m² retenus'].freeze
    MONTANT = 'Montant théorique (F)'
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

    private

    def bloc_destination = @params[:bloc_indemnisation]

    # Les montants théoriques sont ceux que les formules ont calculés sur les
    # lignes actuelles, lus avant de réécrire le bloc. Ils dépendent des m²
    # retenus (saisis par l'instructeur, ce qui relance l'inspection : pas de
    # décalage) et de la famille et du mode écrits ici. Si une écriture change
    # la famille ou le mode d'une ligne qui a déjà des m² retenus (lignes
    # décalées par une culture ajoutée), le bloc plafond garde les anciens
    # montants jusqu'à la modification suivante du dossier : le robot ne
    # relance pas l'inspection après ses propres écritures
    # (VerificationService#avoid_useless_checks_for).
    def ecrit_pertes
      cultures = declarations
      groupes = par_famille_et_mode(cultures)
      montants = montants_actuels
      changed = ecrit_lignes(groupes.map { |g| g.values_at(:famille, :cultures, :mode, :surface) })
      changed |= recopie(@params[:bloc_plafond], plafonds(groupes, montants), PLAFOND)
      changed |= ecrit_surfaces(cultures) if @params[:champ_surfaces].present?
      changed
    end

    def champ_culture = @params[:champ_culture] || 'Culture'
    def champ_bio = @params[:champ_bio] || 'Culture bio ?'
    def champ_surface = @params[:champ_surface] || 'Surface détruite (m²)'

    def declarations
      lignes_du_bloc(@params[:champ]).filter_map do |row|
        culture = champ(row, champ_culture)
        next if culture&.string_value.blank?

        {
          culture: culture.string_value,
          famille: famille(culture),
          mode: champ(row, champ_bio)&.checked ? 'Bio' : 'Non bio',
          surface: champ(row, champ_surface)&.int_value.to_i
        }
      end
    end

    # L'API ne donne pas le nom des colonnes du référentiel, seulement leur id :
    # un identifiant Base64 dont la fin est « .referentiel.data.row.<colonne> ».
    # Cela dépend d'un détail interne de mes-demarches : si le format change,
    # la colonne n'est plus trouvée, la famille reste vide et un avertissement
    # le signale.
    def famille(culture)
      return '' unless culture.respond_to?(:columns) && culture.columns

      column = culture.columns.find { |c| Base64.decode64(c.id)[REFERENTIEL_COLUMN_ID, 1]&.casecmp?('famille') }
      unless column
        Rails.logger.warn("Dossier #{@dossier.number} : colonne « famille » introuvable dans le référentiel de '#{culture.string_value}'")
        return ''
      end
      option_equivalente(column.string_value.to_s, @params[:familles])
    end

    def par_famille_et_mode(cultures)
      cultures.group_by { |c| [c[:famille], c[:mode]] }.map do |(famille, mode), lignes|
        { famille:, mode:, cultures: lignes.map { it[:culture] }.uniq.join(', '), surface: lignes.sum { it[:surface] } }
      end
    end

    # Montants théoriques déjà calculés par les formules, par [famille, mode].
    def montants_actuels
      Array(lignes_actuelles(bloc_destination)).each_with_object(Hash.new(0)) do |row, montants|
        montants[[valeur(row, COLONNES[0]), valeur(row, COLONNES[2])]] += valeur(row, MONTANT).to_f.round
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
  end
end
