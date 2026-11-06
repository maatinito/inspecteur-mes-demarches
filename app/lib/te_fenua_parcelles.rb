# frozen_string_literal: true

# Recopie les parcelles sélectionnées dans un champ carte Te Fenua dans un bloc
# répétable d'annotations privées : une ligne par parcelle, avec le titre et le
# texte d'information affichés par Te Fenua (« Parcelle RH30 (MOOREA-MAIAO) »,
# « Surface (en m²): 14457\nSection: RH... »).
#
# Paramètres facultatifs :
#   champ_titre : annotation recevant le titre (défaut « Parcelle »)
#   champ_texte : annotation recevant le texte Te Fenua complet
#   champs_infos : annotation => ligne du texte Te Fenua, ex.
#     { "Surface (en m²)": "Surface (en m²)", "Ile": "Ile", "Commune associée": "Commune associée" }
#   composition : écrit dans champ_titre un résumé de la parcelle, parties
#     jointes par « - » ; {titre} est le titre Te Fenua, {Clé} une ligne du
#     texte. Une partie dont une valeur manque est omise. Ex.
#     ["{titre}", "{Surface (en m²)} m²", "{Archipel}", "{Ile}", "{Commune associée}"]
#
# L'API mes-demarches n'expose pas ces propriétés : on les redemande au service
# WMS public de Te Fenua (GetFeatureInfo sur un point intérieur de la parcelle,
# comme le fait la carte). Si Te Fenua ne répond pas, on reconstruit le titre et
# le texte à partir des informations cadastrales exposées par l'API.
#
# Le champ source peut traverser un lien vers un autre dossier ou viser la
# carte d'un bloc répétable :
#   champ: "N° du dossier d'inscription CATANAT.Parcelle(s) cultivée(s)"
#   champ: "Culture sinistrée.Zone sinistrée"
class TeFenuaParcelles < FieldChecker
  WMS_URL = 'https://www.tefenua.gov.pf/api/wms'
  CADASTRE_LAYER = 'TEFENUA:CADASTRE'
  # demi-côté (en degrés, ~10 m) de la vignette interrogée autour du point
  DEMI_COTE = 0.0001

  def version
    super + 2
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
    return if parcelles.empty? && bloc_rows.blank?

    dossier_updated(@dossier) if recopie(parcelles)
  end

  private

  def champ_titre = @params[:champ_titre] || 'Parcelle'

  # annotation => clé de info_texte (« Surface (en m²) », « Archipel », « Ile »...)
  def colonnes
    colonnes = (@params[:champs_infos] || {}).to_h { |annotation, cle| [annotation.to_s, ->(p) { p[:infos][cle.to_s] }] }
    colonnes[champ_titre] = @params[:composition].present? ? ->(p) { compose(p) } : ->(p) { p[:titre] }
    colonnes[@params[:champ_texte]] = ->(p) { p[:texte] } if @params[:champ_texte].present?
    colonnes
  end

  # Une parcelle sélectionnée sur plusieurs lignes d'un bloc (une ligne par
  # culture) n'est recopiée qu'une fois.
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

  def geo_areas
    object_field_values(@dossier, @params[:champ], log_empty: false)
      .select { |champ| champ.respond_to?(:__typename) && champ.__typename == 'TeFenuaChamp' }
      .flat_map(&:geo_areas)
      .uniq { |area| area.section.present? ? [area.section, area.numero, area.commune] : area.geometry.coordinates }
  end

  def bloc_rows
    SetAnnotationValue.get_annotation(@dossier, @params[:bloc_destination])&.rows
  end

  # Écrit une ligne par parcelle et vide les lignes en trop (parcelle désélectionnée).
  def recopie(parcelles)
    bloc = SetAnnotationValue.allocate_blocks(@dossier, @demarche.instructeur, @params[:bloc_destination], parcelles.size)
    changed = false
    bloc.rows.each_with_index do |row, index|
      parcelle = parcelles[index]
      colonnes.each do |label, valeur|
        changed |= set_text(row, label, parcelle ? valeur.call(parcelle).to_s : '')
      end
    end
    changed
  end

  # Retourne un booléen de statut (comme save/update), pas un prédicat
  # rubocop:disable Naming/PredicateMethod
  def set_text(row, label, value)
    annotation = row.champs.find { |c| c.label == label }
    unless annotation
      Rails.logger.warn("Champ '#{label}' introuvable dans le bloc '#{@params[:bloc_destination]}' du dossier #{@dossier.number}")
      return false
    end
    return false if SetAnnotationValue.value_of(annotation).to_s == value.to_s

    SetAnnotationValue.raw_set_value(@dossier.id, @demarche.instructeur, annotation.id, value)
    true
  end
  # rubocop:enable Naming/PredicateMethod

  def infos(area)
    point = point_interieur(area.geometry)
    return nil unless point

    tefenua_infos(point, area) || infos_api(area)
  end

  def tefenua_infos(point, area)
    feature = feature_info(*point)
    properties = feature && feature['properties']
    return nil if properties.blank? || properties['info_titre'].blank?

    if area.section.present? && properties['label'] != "#{area.section}#{area.numero}"
      Rails.logger.warn("Te Fenua renvoie la parcelle #{properties['label']} au lieu de #{area.section}#{area.numero} (dossier #{@dossier.number})")
      return nil
    end
    texte = properties['info_texte'].to_s
    { titre: properties['info_titre'], texte:, infos: lignes(texte) }
  end

  # « Surface (en m²): 14457\nIle: Moorea » => { "Surface (en m²)" => "14457", "Ile" => "Moorea" }
  def lignes(texte)
    texte.lines.filter_map do |ligne|
      cle, valeur = ligne.split(':', 2)
      [cle.strip, valeur.strip] if valeur
    end.to_h
  end

  def feature_info(lon, lat)
    response = Typhoeus.get(WMS_URL, params: wms_params(lon, lat), timeout: 30)
    return nil unless response.success?

    JSON.parse(response.body)['features']&.first
  rescue JSON::ParserError => e
    Rails.logger.error("Réponse Te Fenua illisible : #{e.message}")
    nil
  end

  def wms_params(lon, lat)
    {
      SERVICE: 'WMS', VERSION: '1.1.1', REQUEST: 'GetFeatureInfo',
      LAYERS: CADASTRE_LAYER, QUERY_LAYERS: CADASTRE_LAYER, SRS: 'EPSG:4326',
      BBOX: [lon - DEMI_COTE, lat - DEMI_COTE, lon + DEMI_COTE, lat + DEMI_COTE].join(','),
      WIDTH: 101, HEIGHT: 101, X: 50, Y: 50,
      INFO_FORMAT: 'application/json', FEATURE_COUNT: 1, BUFFER: 0
    }
  end

  # Repli : informations cadastrales exposées par l'API mes-demarches.
  def infos_api(area)
    return nil if area.section.blank?

    infos = { 'Section' => area.section, 'Numéro' => area.numero, 'Ile' => area.ile,
              'Commune' => area.commune, 'Commune associée' => area.commune_associee }.compact_blank
    texte = infos.map { |k, v| "#{k}: #{v}" }.join("\n")
    { titre: "Parcelle #{area.section}#{area.numero} (#{area.commune})", texte:, infos: }
  end

  # Point situé à l'intérieur du (premier) polygone : milieu du premier segment
  # intérieur sur l'horizontale médiane. Le centroïde peut tomber hors d'une
  # parcelle concave, pas ce point.
  def point_interieur(geometry)
    case geometry.type
    when 'Point' then geometry.coordinates
    when 'Polygon' then point_interieur_polygone(geometry.coordinates)
    when 'MultiPolygon' then point_interieur_polygone(geometry.coordinates.first)
    end
  end

  def point_interieur_polygone(anneaux)
    ys = anneaux.first.map(&:last)
    y = (ys.min + ys.max) / 2.0
    xs = anneaux.flat_map { |anneau| intersections(anneau, y) }.sort
    return nil if xs.size < 2

    [(xs[0] + xs[1]) / 2.0, y]
  end

  def intersections(anneau, lat)
    anneau.each_cons(2).filter_map do |(x1, y1), (x2, y2)|
      next unless (y1 > lat) != (y2 > lat)

      x1 + ((lat - y1) * (x2 - x1) / (y2 - y1))
    end
  end
end
