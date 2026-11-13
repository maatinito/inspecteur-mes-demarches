# frozen_string_literal: true

# Regroupe par famille les cultures déclarées et les recopie dans un bloc
# répétable d'annotations privées : une ligne par famille, avec la liste des
# cultures de la famille.
#
# Les cultures viennent du bloc `bloc_detail` (une ligne par culture : culture,
# surface, bio / non bio) s'il est rempli, écrites « tomate (75 m² non bio) » ;
# sinon de l'ancienne liste à choix multiple `champ`, écrites « tomate ».
# Le statut bio se déduit des surfaces : surface en bio vide ou nulle → non bio,
# surface en bio ≥ surface cultivée → bio, sinon réponse du demandeur.
#
# La liste est adossée à un référentiel CSV (mode avancé) dont l'API ne renvoie
# que la première colonne (la culture) : la famille vient donc de la
# configuration.
#
# Paramètres :
#   champ : liste à choix multiple source
#   bloc_destination : bloc répétable d'annotations
#   familles : famille => cultures, ex. { "Vanille": ["vanille"], "Cocotiers": ["cocotier"] }
# Paramètres facultatifs :
#   bloc_detail : bloc répétable du formulaire détaillant les cultures
#   champ_culture, champ_surface, champ_bio : colonnes de ce bloc
#     (défauts « Culture », « Surface (m²) », « Bio / non bio »)
#   champ_surface_cultivee, champ_surface_bio : surfaces de l'exploitation
#     (défauts « Surface cultivée », « Surface cultivée en bio »)
#   champ_famille : annotation recevant la famille (défaut « Famille »)
#   champ_cultures : annotation recevant les cultures (défaut « Cultures »)
#   famille_par_defaut : famille des cultures absentes de la table (défaut « Autres »)
class CulturesParFamille < FieldChecker
  include EcritureBloc

  def version
    super + 2
  end

  def required_fields
    super + %i[champ bloc_destination familles]
  end

  def authorized_fields
    super + %i[champ_famille champ_cultures famille_par_defaut bloc_detail champ_culture champ_surface champ_bio
               champ_surface_cultivee champ_surface_bio]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    lignes = regroupe(cultures)
    return if lignes.empty? && lignes_actuelles(@params[:bloc_destination]).blank?

    changed = recopie(@params[:bloc_destination], lignes.map { |famille, textes| [famille, textes.join(', ')] },
                      [champ_famille, champ_cultures])
    dossier_updated(@dossier) if changed
  end

  private

  def champ_famille = @params[:champ_famille] || 'Famille'
  def champ_cultures = @params[:champ_cultures] || 'Cultures'
  def famille_par_defaut = @params[:famille_par_defaut] || 'Autres'
  def champ_culture = @params[:champ_culture] || 'Culture'
  def champ_surface = @params[:champ_surface] || 'Surface (m²)'
  def champ_bio = @params[:champ_bio] || 'Bio / non bio'
  def champ_surface_cultivee = @params[:champ_surface_cultivee] || 'Surface cultivée'
  def champ_surface_bio = @params[:champ_surface_bio] || 'Surface cultivée en bio'

  # culture => famille
  def table
    @table ||= @params[:familles].to_h.each_with_object({}) do |(famille, liste), table|
      Array(liste).each { |culture| table[culture.to_s] = famille.to_s }
    end
  end

  # [[culture, texte écrit]] dans l'ordre du dossier
  def cultures
    detail.presence || ancienne_liste.uniq.map { [it, it] }
  end

  def detail
    return [] if @params[:bloc_detail].blank?

    object_field_values(@dossier, @params[:bloc_detail], log_empty: false)
      .flat_map { Array(it.rows) }
      .filter_map do |row|
        culture = valeur(row.champs, champ_culture).to_s
        [culture, texte(culture, valeur(row.champs, champ_surface), valeur(row.champs, champ_bio))] if culture.present?
      end
  end

  def texte(culture, surface, reponse)
    return culture if surface.blank?

    "#{culture} (#{["#{surface} m²", statut(reponse)].compact.join(' ')})"
  end

  def statut(reponse)
    bio = surface(champ_surface_bio).to_i
    return 'non bio' if bio <= 0
    return 'bio' if bio >= surface(champ_surface_cultivee).to_i

    reponse.presence&.downcase
  end

  def surface(label)
    valeur(@dossier.champs, label)
  end

  def valeur(champs, label)
    champ_value(select_champ(champs, label).first).presence
  end

  # `stringValue` joint les cultures par « , » alors que certains libellés
  # contiennent une virgule (« pépinière maraichère, aromatique ») : on
  # reconnaît d'abord les libellés connus.
  def ancienne_liste
    object_field_values(@dossier, @params[:champ], log_empty: false)
      .flat_map { |champ| decoupe(champ.string_value.to_s) }
  end

  def decoupe(texte)
    connues = table.keys.sort_by { -it.size }
    resultat = []
    until texte.empty?
      culture = connues.find { |c| texte == c || texte.start_with?("#{c}, ") } || texte.split(', ', 2).first
      resultat << culture
      texte = texte.delete_prefix(culture).delete_prefix(', ')
    end
    resultat
  end

  def famille(culture)
    table.fetch(culture) do
      Rails.logger.warn("Culture '#{culture}' absente de la table des familles (dossier #{@dossier.number})")
      famille_par_defaut
    end
  end

  # [[famille, [textes]]] dans l'ordre des familles de la configuration
  def regroupe(cultures)
    groupes = cultures.group_by { |culture, _texte| famille(culture) }.transform_values { it.map(&:last) }
    ordre = @params[:familles].to_h.keys.map(&:to_s) << famille_par_defaut
    groupes.sort_by { |famille, _| ordre.index(famille) || ordre.size }
  end
end
