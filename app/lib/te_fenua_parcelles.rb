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
    return if parcelles.empty? && bloc_rows.blank?

    dossier_updated(@dossier) if recopie(parcelles)
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
