module Diese
  module RateCheck
    def rate_check_version
      1
    end

    def required_fields
      super + %i[message_taux_depasse]
    end

    def check(dossier)
      field = activity_field
      @max_rate = RATES.dig(field.primary_value, field.secondary_value)
      throw "Secteur inconnu #{field.primary_value};#{field.secondary_value} dasn le dossier #{dossier.number}" if @max_rate.blank?
      super
    end

    private

    CHECKS = (EtatPrevisionnelCheck::CHECKS + %i[max_rate]).freeze

    RATES = {
      "Tourisme" => {
        "Hébergement touristique terrestre" => 40,
        "Hébergement touristique flottant" => 60,
        "Prestataires touristiques et culturels" => 60,
      },
      "Autres secteurs d'activité éligibles" => {
        "Transport aérien" => 40,
        "Commerces et activités présents dans les hôtels" => 40,
        "Commerces et activités présents sur la plateforme aéroportuaire de Tahiti-Faa'a et dans les aérodromes des îles" => 50,
        "Bijouterie, artisanat d'art" => 80,
        "Boutiques de souvenirs et curios" => 80,
        "Perliculture" => 90,
        "Discothèques et assimilées" => 90,
        "Prestataires dans le domaine de l'évènementiel (foires, expositions, évènements sportifs, etc.)" => 90,
      }
    }.freeze

    def check_max_rate(line)
      value = line[:taux]
      value <= @max_rate / 100.0 ? true : "#{@params[:message_taux_depasse]}#{@max_rate}%"
    end
  end
end