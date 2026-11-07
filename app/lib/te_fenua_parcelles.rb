# frozen_string_literal: true

# Recopie les parcelles sélectionnées dans un champ carte Te Fenua dans un bloc
# répétable d'annotations privées : une ligne par parcelle, avec un titre
# (« Parcelle RH26 (MOOREA-MAIAO) ») et un texte d'information
# (« Surface (en m²): 7203\nSection: RH... »).
#
# Paramètres facultatifs :
#   champ_titre : annotation recevant le titre (défaut « Parcelle »)
#   champ_texte : annotation recevant le texte d'information complet
#   champs_infos : annotation => ligne du texte d'information, ex.
#     { "Surface (en m²)": "Surface (en m²)", "Ile": "Ile", "Commune associée": "Commune associée" }
#   composition : écrit dans champ_titre un résumé de la parcelle, parties
#     jointes par « - » ; {titre} est le titre, {Clé} une ligne du texte.
#     Une partie dont une valeur manque est omise. Ex.
#     ["{titre}", "{Surface (en m²)} m²", "{Ile}", "{Commune associée}"]
#
# Lignes du texte : Surface (en m²), Section, Numéro, Ile, Commune, Commune
# associée. L'API mes-demarches ne donne pas la surface d'une sélection Te
# Fenua : elle est calculée sur la géométrie, comme la carte de la demande
# (aire sphérique d'OpenLayers). C'est une valeur approchée, qui peut s'écarter
# de quelques dixièmes de pour cent de la surface cadastrale.
#
# Le champ source peut traverser un lien vers un autre dossier ou viser la
# carte d'un bloc répétable :
#   champ: "N° du dossier d'inscription CATANAT.Parcelle(s) cultivée(s)"
#   champ: "Culture sinistrée.Zone sinistrée"
class TeFenuaParcelles < FieldChecker
  include EcritureBloc

  # rayon terrestre utilisé par ol/sphere (getArea)
  RAYON_TERRE = 6_371_008.8

  def version
    super + 3
  end

  def required_fields
    super + %i[champ bloc_destination]
  end

  def authorized_fields
    super + %i[champ_titre champ_texte champs_infos composition]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    parcelles = geo_areas.map { |area| infos(area) }.compact
    return if parcelles.empty? && lignes_actuelles(@params[:bloc_destination]).blank?

    colonnes = self.colonnes
    lignes = parcelles.map { |parcelle| colonnes.values.map { |valeur| valeur.call(parcelle).to_s } }
    dossier_updated(@dossier) if recopie(@params[:bloc_destination], lignes, colonnes.keys)
  end

  private

  def champ_titre = @params[:champ_titre] || 'Parcelle'

  # annotation => ligne du texte d'information (« Surface (en m²) », « Ile »...)
  def colonnes
    colonnes = (@params[:champs_infos] || {}).to_h { |annotation, cle| [annotation.to_s, ->(p) { p[:infos][cle.to_s] }] }
    colonnes[champ_titre] = @params[:composition].present? ? ->(p) { compose(p) } : ->(p) { p[:titre] }
    colonnes[@params[:champ_texte]] = ->(p) { p[:texte] } if @params[:champ_texte].present?
    colonnes
  end

  def compose(parcelle)
    Array(@params[:composition]).filter_map do |partie|
      vide = false
      texte = partie.to_s.gsub(/\{([^{}]+)\}/) do
        valeur = ::Regexp.last_match(1) == 'titre' ? parcelle[:titre] : parcelle[:infos][::Regexp.last_match(1)]
        vide ||= valeur.blank?
        valeur.to_s
      end
      texte unless vide
    end.join(' - ')
  end

  # Une parcelle sélectionnée sur plusieurs lignes d'un bloc (une ligne par
  # culture) n'est recopiée qu'une fois.
  def geo_areas
    champs = object_field_values(@dossier, @params[:champ], log_empty: false)
             .select { |champ| champ.respond_to?(:__typename) && champ.__typename == 'TeFenuaChamp' }
    return [] if champs.empty?

    zones = zones_par_champ(dossiers_sources)
    champs.flat_map { |champ| zones.fetch(champ.id, []) }
          .uniq { |area| area.section.present? ? [area.section, area.numero, area.commune] : area.geometry.coordinates }
  end

  # Le dossier et les dossiers liés que traverse le chemin du champ
  # (« N° du dossier d'inscription CATANAT.Parcelle(s) cultivée(s) »).
  def dossiers_sources
    parties = @params[:champ].to_s.split('.')
    lies = (1...parties.size).flat_map do |n|
      object_field_values(@dossier, parties.first(n).join('.'), log_empty: false)
        .filter_map { |champ| champ.dossier&.number if champ.respond_to?(:dossier) }
    end
    [@dossier.number, *lies].uniq
  end

  # id du champ carte => zones. Les géométries ne sont pas dans la requête
  # commune des dossiers (fragment ChampInfo) : on les charge ici. Une erreur
  # interrompt la tâche : une liste vide ferait vider le bloc.
  def zones_par_champ(numeros)
    numeros.each_with_object({}) do |numero, zones|
      reponse = MesDemarches.query(MesDemarches::Queries::TeFenuaGeoAreas, variables: { number: numero })
      raise StandardError, reponse.errors.messages.values.join(', ') if reponse.errors.present?

      dossier = reponse.data.dossier
      [*dossier.champs, *dossier.annotations].each do |champ|
        champs = champ.respond_to?(:rows) ? champ.rows.flat_map(&:champs) : [champ]
        champs.each { |c| zones[c.id] = c.geo_areas if c.respond_to?(:geo_areas) }
      end
    end
  end

  def infos(area)
    surface = surface(area.geometry)
    infos = { 'Surface (en m²)' => surface&.round&.to_s, 'Section' => area.section, 'Numéro' => area.numero,
              'Ile' => area.ile, 'Commune' => area.commune, 'Commune associée' => area.commune_associee }.compact_blank
    return nil if infos.empty?

    titre = area.section.present? ? "Parcelle #{area.section}#{area.numero} (#{area.commune})" : 'Zone sélectionnée'
    { titre:, texte: infos.map { |cle, valeur| "#{cle}: #{valeur}" }.join("\n"), infos: }
  end

  # Surface en m² d'un polygone ou multipolygone en EPSG:4326, nil pour un point
  def surface(geometry)
    case geometry.type
    when 'Polygon' then surface_polygone(geometry.coordinates)
    when 'MultiPolygon' then geometry.coordinates.sum { |polygone| surface_polygone(polygone) }
    end
  end

  # anneau extérieur moins les trous
  def surface_polygone(anneaux)
    exterieur, *trous = anneaux
    surface_anneau(exterieur) - trous.sum { |trou| surface_anneau(trou) }
  end

  # Aire sphérique d'un anneau, formule de ol/sphere (getArea)
  def surface_anneau(anneau)
    rad = Math::PI / 180
    somme = anneau.each_index.sum do |i|
      x1, y1 = anneau[i]
      x2, y2 = anneau[(i + 1) % anneau.size]
      (x2 - x1) * rad * (2 + Math.sin(y1 * rad) + Math.sin(y2 * rad))
    end
    (somme * RAYON_TERRE * RAYON_TERRE / 2).abs
  end
end
