# frozen_string_literal: true

module Calculs
  # Lit un champ carte Te Fenua : sa valeur est un GeoJSON dont chaque marqueur porte la commune, l'île et la
  # parcelle cadastrale (section, numéro). Le robot ne sait pas l'afficher autrement que « TeFenuaChamp » : ce
  # calcul en tire un texte imprimable. Seul le premier marqueur compte.
  # Sorties : « <champ>.commune », « <champ>.ile », « <champ>.parcelle » (« AB 5 »),
  # « <champ>.lieu » (« PAPEETE (Tahiti), parcelle AB 5 ») ; chaînes vides si la carte est vide ou illisible.
  class TeFenua < FieldChecker
    CLES = %w[commune ile parcelle lieu].freeze

    def version
      super + 1
    end

    def required_fields
      super + %i[champ]
    end

    def process_row(dossier, output)
      libelle = @params[:champ]
      valeurs = decrire(premier_marqueur(dossier, libelle))
      CLES.each { |cle| output["#{libelle}.#{cle}"] = valeurs[cle] }
    end

    private

    def premier_marqueur(dossier, libelle)
      champ = object_field_values(dossier, libelle, log_empty: false).first
      texte = champ&.string_value.to_s
      return {} if texte.blank?

      # Forme attendue : { markers: { features: [ { properties: { … } } ] } }. Toute autre forme (valeurs
      # historiques en tableau, null…) donne un lieu vide plutôt qu'une erreur qui bloquerait le document.
      geo = JSON.parse(texte)
      marqueurs = geo.is_a?(Hash) ? geo['markers'] : nil
      features = marqueurs.is_a?(Hash) ? marqueurs['features'] : nil
      premier = features.is_a?(Array) ? features.first : nil
      proprietes = premier.is_a?(Hash) ? premier['properties'] : nil
      proprietes.is_a?(Hash) ? proprietes : {}
    rescue JSON::ParserError
      {}
    end

    def decrire(proprietes)
      commune = proprietes['commune'].to_s
      ile = proprietes['ile'].to_s
      parcelle = [proprietes['section'], proprietes['numero']].compact.join(' ').strip
      lieu = [commune, ile.present? && "(#{ile})"].select(&:present?).join(' ')
      lieu = [lieu, parcelle.present? && "parcelle #{parcelle}"].select(&:present?).join(', ') if lieu.present?
      { 'commune' => commune, 'ile' => ile, 'parcelle' => parcelle, 'lieu' => lieu }
    end
  end
end
