module Diese
  module RateCheck
    attr_writer :month

    def rate_check_version
      3
    end

    def required_fields
      super + %i[message_taux_depasse]
    end

    def check(dossier)
      field = activity_field
      @max_rates = RATES.dig(field.primary_value, field.secondary_value)
      throw "Secteur inconnu #{field.primary_value};#{field.secondary_value} dans le dossier #{dossier.number}" if @max_rates.blank?
      super
    end

    private

    CHECKS = (EtatPrevisionnelCheck::CHECKS + %i[max_rate]).freeze

    RATES = {
      'Tourisme' => {
        'Hébergement touristique terrestre' => [70, 50, 40],
        'Meublés du tourisme' => [40, 40, 40],
        'Hébergement touristique flottant' => [70, 50, 40],
        'Prestataires touristiques et culturels' => [70, 60, 60]
      },
      "Autres secteurs d'activité éligibles" => {
        'Restauration' => [70, 50, 40],
        'Transport aérien' => [50, 40, 40],
        'Commerces et activités présents dans les hôtels' => [40, 40, 40],
        "Commerces et activités présents sur la plateforme aéroportuaire de Tahiti-Faa'a et dans les aérodromes des îles" => [50, 50, 50],
        "Bijouterie, artisanat d'art" => [80, 80, 80],
        'Boutiques de souvenirs et curios' => [80, 80, 80],
        'Perliculture' => [90, 90, 90],
        'Discothèques et assimilées' => [90, 90, 90],
        "Prestataires dans le domaine de l'évènementiel (foires, expositions, évènements sportifs, etc.)" => [90, 90, 90]
      }
    }.freeze

    def check_max_rate(line)
      value = line[:taux]
      value = value.to_f if value.is_a?(String)
      throw "Mois inconnu dans le dossier #{dossier.number}" if @month.blank?
      max_rate = @max_rates[@month]
      value <= (max_rate / 100.0) ? true : "#{@params[:message_taux_depasse]}#{max_rate}%"
    end
  end
end
