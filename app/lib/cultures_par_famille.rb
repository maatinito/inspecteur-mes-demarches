# frozen_string_literal: true

# Regroupe par famille les cultures choisies dans une liste à choix multiple et
# les recopie dans un bloc répétable d'annotations privées : une ligne par
# famille, avec la liste des cultures de la famille.
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
#   champ_famille : annotation recevant la famille (défaut « Famille »)
#   champ_cultures : annotation recevant les cultures (défaut « Cultures »)
#   famille_par_defaut : famille des cultures absentes de la table (défaut « Autres »)
class CulturesParFamille < FieldChecker
  include EcritureBloc

  def version
    super + 1
  end

  def required_fields
    super + %i[champ bloc_destination familles]
  end

  def authorized_fields
    super + %i[champ_famille champ_cultures famille_par_defaut]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    lignes = regroupe(cultures)
    return if lignes.empty? && lignes_actuelles(@params[:bloc_destination]).blank?

    changed = recopie(@params[:bloc_destination], lignes.map { |famille, cultures| [famille, cultures.join(', ')] },
                      [champ_famille, champ_cultures])
    dossier_updated(@dossier) if changed
  end

  private

  def champ_famille = @params[:champ_famille] || 'Famille'
  def champ_cultures = @params[:champ_cultures] || 'Cultures'
  def famille_par_defaut = @params[:famille_par_defaut] || 'Autres'

  # culture => famille
  def table
    @table ||= @params[:familles].to_h.each_with_object({}) do |(famille, liste), table|
      Array(liste).each { |culture| table[culture.to_s] = famille.to_s }
    end
  end

  # Cultures choisies, dans l'ordre du dossier. `stringValue` les joint par
  # « , » alors que certains libellés contiennent une virgule (« pépinière
  # maraichère, aromatique ») : on reconnaît d'abord les libellés connus.
  def cultures
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

  # [[famille, [cultures]]] dans l'ordre des familles de la configuration
  def regroupe(cultures)
    groupes = cultures.uniq.group_by do |culture|
      table.fetch(culture) do
        Rails.logger.warn("Culture '#{culture}' absente de la table des familles (dossier #{@dossier.number})")
        famille_par_defaut
      end
    end
    ordre = @params[:familles].to_h.keys.map(&:to_s) << famille_par_defaut
    groupes.sort_by { |famille, _| ordre.index(famille) || ordre.size }
  end
end
